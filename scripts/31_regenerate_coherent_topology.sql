-- ============================================================================
-- 31_regenerate_coherent_topology.sql
-- ============================================================================
-- Regenerates the FLUX grid topology as a spatially COHERENT, DETERMINISTIC
-- hierarchy:  Substation -> Circuit(Feeder) -> Transformer -> Pole -> Meter
--
-- WHY THIS EXISTS
--   The previous dataset was spatially incoherent: children were placed at
--   independent uniform random coordinates across the whole Houston bbox and
--   then assigned a parent with random.choice(), so transformer->substation
--   distances averaged ~41 km (the expected distance between two uniform
--   points in an ~89 km box) instead of the ~4.5 km a real distribution grid
--   shows. Separately, several views fabricated coordinates with bare
--   RANDOM(), which in Snowflake returns a SIGNED 64-BIT INTEGER, not a
--   [0,1) float -- producing "latitudes" of ~4.4e17 and NaN distances.
--
-- DETERMINISM CONTRACT
--   Every derived value comes from UNIFORM(0::FLOAT,1::FLOAT,HASH(key,salt)).
--   Verified: HASH-seeded UNIFORM returns identical values across separate
--   query executions, so this script is reproducible and re-runnable.
--   NEVER use RANDOM() here. NEVER use ABS(HASH(x)) % N -- ABS(-2^63)
--   overflows negative in two's complement.
--
-- PLACEMENT MATH
--   bearing  = 2*PI()*u1
--   dist_km  = max_radius_km * SQRT(u2)   -- SQRT gives area-uniform on a disc;
--                                            without it points cluster centrally
--   1 deg lat = 111.132 - 0.559*cos(2*lat) + 0.001*cos(4*lat)  (latitude-parameterised)
--   1 deg lon = 111.320 * cos(lat)                             (converges at the poles)
--
--   max_radius_km per level is 1.5x the target mean, because for sqrt-sampled
--   discs E[dist] = (2/3)*R. Targets come from GEOGRAPHIC_REALISM_AUDIT_JAN5_2026.md,
--   which measured this dataset while it was still coherent.
--     transformer -> substation      R = 6.80 km   (audit mean 4527 m)
--     transformer -> circuit envelope R = 4.00 km  (keeps circuit span < 10 km)
--     pole        -> transformer     R = 0.32 km   (audit 216 m pad-mounted)
--     meter       -> pole            R = 0.36 km   (audit mean 241 m service drop)
--
-- HARD CARVE-OUT
--   AMI_INTERVAL_READINGS holds 288,000,000 rows keyed by METER_ID.
--   METER_ID IS NEVER CHANGED. Meters are RE-LINKED to new parents and moved
--   into their new pole's service-drop envelope. AMI stays valid.
--
-- ANCHORS
--   The 275 substation anchors are REAL Houston-area substations (names and
--   coordinates) sourced from the operational Postgres store, re-keyed to the
--   canonical 4-digit space SUB-HOU-0001..SUB-HOU-0275. 4-digit because a real
--   utility (CenterPoint has 860+ transmission substations alone) outgrows 3.
--
-- Usage:
--   snow sql -f scripts/31_regenerate_coherent_topology.sql -D "database=FLUX_DB" -D "schema=PRODUCTION"
-- ============================================================================

USE DATABASE IDENTIFIER('<% database %>');
USE SCHEMA IDENTIFIER('<% schema %>');

-- ---------------------------------------------------------------------------
-- PHASE 0 -- Anchors + permanent old->new provenance map
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE SUBSTATION_ID_XREF (
    SOURCE_SYSTEM    VARCHAR,
    SOURCE_ID        VARCHAR,
    CANONICAL_ID     VARCHAR,
    SUBSTATION_NAME  VARCHAR,
    LATITUDE         FLOAT,
    LONGITUDE        FLOAT,
    CAPACITY_MVA     NUMBER
) COMMENT = 'PERMANENT provenance map for the 2026-07-29 topology regeneration. Maps every legacy substation key space (SUB_0001 underscore, SUB-HOU-### 3-digit, SUB-0### ) to the canonical SUB-HOU-#### 4-digit key. Keep this table: it is the rollback and audit key, not scratch.';

INSERT INTO SUBSTATION_ID_XREF
    (SOURCE_SYSTEM, SOURCE_ID, CANONICAL_ID, SUBSTATION_NAME, LATITUDE, LONGITUDE, CAPACITY_MVA)
VALUES
    ('POSTGRES','SUB-HOU-089','SUB-HOU-0001','Addicks Substation',29.822803,-95.572897,280.0),
    ('POSTGRES','SUB-HOU-085','SUB-HOU-0002','Airline Substation',29.818677,-95.389376,270.0),
    ('POSTGRES','SUB-HOU-100','SUB-HOU-0003','Aldine Substation',29.901732,-95.370386,270.0),
    ('POSTGRES','SUB-HOU-030','SUB-HOU-0004','Alief Substation',29.700425,-95.581783,270.0),
    ('POSTGRES','SUB-HOU-002','SUB-HOU-0005','Almeda Substation',29.630098,-95.403624,270.0),
    ('POSTGRES','SUB-0018','SUB-HOU-0006','Alta Loma Substation',29.391578,-95.091006,111600.0),
    ('POSTGRES','SUB-HOU-127','SUB-HOU-0007','Alvin Substation',29.43371,-95.253998,280.0),
    ('POSTGRES','SUB-0010','SUB-HOU-0008','Angleton Substation',29.226771,-95.42884,85500.0),
    ('POSTGRES','SUB-0023','SUB-HOU-0009','Arcola Substation',29.489056,-95.466531,85500.0),
    ('POSTGRES','SUB-HOU-116','SUB-HOU-0010','Atascocita Substation',30.004896,-95.097025,270.0),
    ('POSTGRES','SUB-HOU-165','SUB-HOU-0011','BASF Substation',29.001688,-95.396616,270.0),
    ('POSTGRES','SUB-HOU-111','SUB-HOU-0012','Bammel Substation',29.98266,-95.502597,280.0),
    ('POSTGRES','SUB-HOU-034','SUB-HOU-0013','Barker Substation',29.71168,-95.64324,270.0),
    ('POSTGRES','SUB-HOU-046','SUB-HOU-0014','Baytown Substation',29.733362,-95.004863,280.0),
    ('POSTGRES','SUB-0047','SUB-HOU-0015','Bayway Substation',29.609416,-95.049553,150000.0),
    ('POSTGRES','SUB-HOU-090','SUB-HOU-0016','Berry Substation',29.839471,-95.353702,270.0),
    ('POSTGRES','SUB-HOU-091','SUB-HOU-0017','Bertwood Substation',29.843965,-95.31416,280.0),
    ('POSTGRES','SUB-HOU-128','SUB-HOU-0018','Big Creek Substation',29.471148,-95.750866,280.0),
    ('POSTGRES','SUB-HOU-160','SUB-HOU-0019','Biport Substation',28.986081,-95.338526,270.0),
    ('POSTGRES','SUB-HOU-039','SUB-HOU-0020','Blodgett Substation',29.720959,-95.364524,270.0),
    ('POSTGRES','SUB-HOU-154','SUB-HOU-0021','Booster Substation',28.962858,-95.391723,270.0),
    ('POSTGRES','SUB-HOU-019','SUB-HOU-0022','Brays Substation',29.683754,-95.447836,270.0),
    ('POSTGRES','SUB-0005','SUB-HOU-0023','Brazosport Substation',29.009659,-95.432653,111600.0),
    ('POSTGRES','SUB-HOU-075','SUB-HOU-0024','Brittmoore Substation',29.794344,-95.572156,280.0),
    ('POSTGRES','SUB-HOU-143','SUB-HOU-0025','Bryan Substation',28.919501,-95.376069,270.0),
    ('POSTGRES','SUB-HOU-067','SUB-HOU-0026','Busch Substation - Northwest',29.776236,-95.272707,280.0),
    ('POSTGRES','SUB-HOU-065','SUB-HOU-0027','Busch Substation - Southeast',29.7749,-95.267867,270.0),
    ('POSTGRES','SUB-HOU-162','SUB-HOU-0028','Camden Substation',28.988132,-95.357392,270.0),
    ('POSTGRES','SUB-HOU-083','SUB-HOU-0029','Campbell Substation',29.818242,-95.524672,280.0),
    ('POSTGRES','SUB-HOU-006','SUB-HOU-0030','Cardiff Substation',29.65363,-95.154762,270.0),
    ('POSTGRES','SUB-HOU-061','SUB-HOU-0031','Cedar Bayou Substation',29.757895,-94.950143,270.0),
    ('POSTGRES','SUB-HOU-066','SUB-HOU-0032','Channelview Substation',29.775639,-95.150974,270.0),
    ('POSTGRES','SUB-HOU-000','SUB-HOU-0033','Chocolate Bayou Substation',29.627878,-95.35269,280.0),
    ('POSTGRES','SUB-0046','SUB-HOU-0034','Clear Lake Substation',29.608366,-95.126485,85500.0),
    ('POSTGRES','SUB-HOU-134','SUB-HOU-0035','Clinton Substation - Northeast',29.760932,-95.299663,270.0),
    ('POSTGRES','SUB-HOU-060','SUB-HOU-0036','Clinton Substation - Southwest',29.75554,-95.301167,270.0),
    ('POSTGRES','SUB-HOU-016','SUB-HOU-0037','Clodine Substation',29.674791,-95.620718,280.0),
    ('POSTGRES','SUB-HOU-008','SUB-HOU-0038','College Substation',29.659718,-95.244847,270.0),
    ('POSTGRES','SUB-HOU-167','SUB-HOU-0039','Copper Substation',29.006759,-95.405127,270.0),
    ('POSTGRES','SUB-HOU-144','SUB-HOU-0040','Cortez Substation',28.92486,-95.324006,270.0),
    ('POSTGRES','SUB-0035','SUB-HOU-0041','Crabb River Road Substation',29.562798,-95.698516,85500.0),
    ('POSTGRES','SUB-HOU-068','SUB-HOU-0042','Crockett Substation',29.777228,-95.380121,280.0),
    ('POSTGRES','SUB-HOU-096','SUB-HOU-0043','Crosby Substation',29.872831,-95.019754,270.0),
    ('POSTGRES','SUB-HOU-108','SUB-HOU-0044','Cy-Fair Substation',29.948003,-95.672579,280.0),
    ('POSTGRES','SUB-HOU-168','SUB-HOU-0045','DSM Substation',29.010336,-95.369707,270.0),
    ('POSTGRES','SUB-HOU-126','SUB-HOU-0046','Damon Substation',29.291757,-95.729257,270.0),
    ('POSTGRES','SUB-HOU-027','SUB-HOU-0047','Deer Park Substation',29.692403,-95.128949,280.0),
    ('POSTGRES','SUB-HOU-093','SUB-HOU-0048','Deihl Substation',29.854703,-95.476095,280.0),
    ('POSTGRES','SUB-0044','SUB-HOU-0049','Dewalt Substation',29.604516,-95.563696,85500.0),
    ('POSTGRES','SUB-0004','SUB-HOU-0050','Dow Substation',28.986183,-95.358162,111600.0),
    ('POSTGRES','SUB-HOU-059','SUB-HOU-0051','Downtown Substation',29.75512,-95.373794,270.0),
    ('POSTGRES','SUB-HOU-011','SUB-HOU-0052','Drouet Substation',29.667151,-95.283038,280.0),
    ('POSTGRES','SUB-HOU-133','SUB-HOU-0053','Dunlavy Substation',29.752641,-95.401858,280.0),
    ('POSTGRES','SUB-HOU-045','SUB-HOU-0054','Dunvale Substation',29.733087,-95.518972,280.0),
    ('POSTGRES','SUB-HOU-054','SUB-HOU-0055','East Side Substation',29.747068,-95.353109,270.0),
    ('POSTGRES','SUB-HOU-072','SUB-HOU-0056','Echo Substation',29.785409,-95.520694,270.0),
    ('POSTGRES','SUB-0034','SUB-HOU-0057','El Dorado Substation',29.561908,-95.141628,111600.0),
    ('POSTGRES','SUB-0040','SUB-HOU-0058','Ellington Substation',29.588178,-95.180542,111600.0),
    ('POSTGRES','SUB-HOU-076','SUB-HOU-0059','Eureka Substation',29.794834,-95.433477,280.0),
    ('POSTGRES','SUB-HOU-099','SUB-HOU-0060','Fairbanks Substation',29.899978,-95.501854,270.0),
    ('POSTGRES','SUB-HOU-004','SUB-HOU-0061','Fairmont Substation',29.649528,-95.102761,280.0),
    ('POSTGRES','SUB-HOU-023','SUB-HOU-0062','Fannin Substation',29.689584,-95.40843,270.0),
    ('POSTGRES','SUB-HOU-012','SUB-HOU-0063','Fondren Substation',29.667887,-95.509355,270.0),
    ('POSTGRES','SUB-HOU-063','SUB-HOU-0064','Franklin Substation',29.766087,-95.367776,270.0),
    ('POSTGRES','SUB-HOU-145','SUB-HOU-0065','Franklins Camp Substation',28.928147,-95.563901,270.0),
    ('POSTGRES','SUB-HOU-078','SUB-HOU-0066','Franz Substation',29.803026,-95.753846,280.0),
    ('POSTGRES','SUB-0001','SUB-HOU-0067','Freeport Substation',28.940345,-95.348456,150000.0),
    ('POSTGRES','SUB-0026','SUB-HOU-0068','Friendswood Substation',29.522657,-95.153378,85500.0),
    ('POSTGRES','SUB-HOU-104','SUB-HOU-0069','Fry Road Substation',29.91268,-95.724422,280.0),
    ('POSTGRES','SUB-HOU-062','SUB-HOU-0070','Gable Street Substation',29.764427,-95.352508,270.0),
    ('POSTGRES','SUB-HOU-052','SUB-HOU-0071','Galena Park Substation',29.745839,-95.230821,280.0),
    ('POSTGRES','SUB-HOU-005','SUB-HOU-0072','Garden Villas Substation',29.651032,-95.314435,280.0),
    ('POSTGRES','SUB-HOU-044','SUB-HOU-0073','Garrott Substation',29.732891,-95.385982,270.0),
    ('POSTGRES','SUB-HOU-110','SUB-HOU-0074','Gears Substation',29.964721,-95.440075,270.0),
    ('POSTGRES','SUB-HOU-094','SUB-HOU-0075','Gertie Substation',29.86358,-95.683935,270.0),
    ('POSTGRES','SUB-HOU-092','SUB-HOU-0076','Glenwood Substation',29.85059,-95.265944,270.0),
    ('POSTGRES','SUB-HOU-033','SUB-HOU-0077','Goodyear Substation',29.706203,-95.256986,280.0),
    ('POSTGRES','SUB-HOU-032','SUB-HOU-0078','Grant Substation',29.703377,-95.401636,270.0),
    ('POSTGRES','SUB-HOU-137','SUB-HOU-0079','Greens Bayou 345kV Substation',29.818459,-95.218259,280.0),
    ('POSTGRES','SUB-HOU-138','SUB-HOU-0080','Greens Bayou 69kV Substation',29.820097,-95.220855,270.0),
    ('POSTGRES','SUB-HOU-109','SUB-HOU-0081','Greens Road Substation',29.950826,-95.333223,280.0),
    ('POSTGRES','SUB-HOU-028','SUB-HOU-0082','Gulfgate Substation',29.693107,-95.300103,270.0),
    ('POSTGRES','SUB-0041','SUB-HOU-0083','Hall Substation',29.589329,-95.240205,85500.0),
    ('POSTGRES','SUB-HOU-088','SUB-HOU-0084','Haney Substation',29.821054,-94.990816,270.0),
    ('POSTGRES','SUB-HOU-084','SUB-HOU-0085','Hardy Substation',29.818574,-95.353486,270.0),
    ('POSTGRES','SUB-HOU-130','SUB-HOU-0086','Harrisburg Substation',29.714922,-95.265202,270.0),
    ('POSTGRES','SUB-HOU-053','SUB-HOU-0087','Hayes Substation',29.746348,-95.574375,280.0),
    ('POSTGRES','SUB-HOU-135','SUB-HOU-0088','Heights Substation',29.782362,-95.398515,280.0),
    ('POSTGRES','SUB-HOU-102','SUB-HOU-0089','Hidden Valley Substation',29.911204,-95.42301,280.0),
    ('POSTGRES','SUB-HOU-077','SUB-HOU-0090','Highlands Substation',29.800751,-95.031343,270.0),
    ('POSTGRES','SUB-HOU-041','SUB-HOU-0091','Hillcroft Substation',29.722109,-95.497696,270.0),
    ('POSTGRES','SUB-0015','SUB-HOU-0092','Hitchcock Substation',29.347478,-95.015899,200000.0),
    ('POSTGRES','SUB-HOU-017','SUB-HOU-0093','Holmes Substation',29.679453,-95.372117,270.0),
    ('POSTGRES','SUB-HOU-115','SUB-HOU-0094','Humble Substation',30.000071,-95.235061,270.0),
    ('POSTGRES','SUB-HOU-132','SUB-HOU-0095','Hyde Park Substation',29.747902,-95.384416,270.0),
    ('POSTGRES','SUB-0042','SUB-HOU-0096','Imperial Substation',29.594614,-95.630133,85500.0),
    ('POSTGRES','SUB-HOU-057','SUB-HOU-0097','Industrial Substation',29.752124,-95.185853,280.0),
    ('POSTGRES','SUB-HOU-112','SUB-HOU-0098','Intercontinental Substation',29.986905,-95.367404,270.0),
    ('POSTGRES','SUB-0045','SUB-HOU-0099','Intermediate Substation',29.606675,-95.446888,85500.0),
    ('POSTGRES','SUB-HOU-056','SUB-HOU-0100','Jacintoport Substation',29.751809,-95.125192,270.0),
    ('POSTGRES','SUB-HOU-037','SUB-HOU-0101','Jeanetta Substation',29.7188,-95.53669,270.0),
    ('POSTGRES','SUB-0002','SUB-HOU-0102','Jones Creek Substation',28.957577,-95.380999,112500.0),
    ('POSTGRES','SUB-0024','SUB-HOU-0103','Karsten Substation',29.490708,-95.430059,85500.0),
    ('POSTGRES','SUB-0029','SUB-HOU-0104','Kemah Substation',29.538278,-95.026329,111600.0),
    ('POSTGRES','SUB-HOU-140','SUB-HOU-0105','King Substation',29.91534,-95.216315,290.0),
    ('POSTGRES','SUB-HOU-121','SUB-HOU-0106','Kingwood Substation',30.054442,-95.189375,270.0),
    ('POSTGRES','SUB-HOU-043','SUB-HOU-0107','Kirby Substation',29.729723,-95.422894,270.0),
    ('POSTGRES','SUB-HOU-118','SUB-HOU-0108','Klein Substation',30.023906,-95.570165,270.0),
    ('POSTGRES','SUB-HOU-113','SUB-HOU-0109','Kluge Substation',29.989523,-95.618403,270.0),
    ('POSTGRES','SUB-HOU-014','SUB-HOU-0110','Knight Substation',29.672254,-95.413089,280.0),
    ('POSTGRES','SUB-HOU-142','SUB-HOU-0111','Kuykendahl Substation',30.089147,-95.527077,280.0),
    ('POSTGRES','SUB-HOU-009','SUB-HOU-0112','La Porte Substation',29.664839,-95.016126,270.0),
    ('POSTGRES','SUB-0006','SUB-HOU-0113','Lake Jackson Substation',29.052934,-95.423978,111600.0),
    ('POSTGRES','SUB-HOU-103','SUB-HOU-0114','Lauder Substation',29.911245,-95.321535,270.0),
    ('POSTGRES','SUB-HOU-079','SUB-HOU-0115','Liberty Substation',29.807004,-95.285522,270.0),
    ('POSTGRES','SUB-HOU-139','SUB-HOU-0116','Little York Substation',29.864167,-95.429919,280.0),
    ('POSTGRES','SUB-0013','SUB-HOU-0117','Liverpool Substation',29.279128,-95.294859,180000.0),
    ('POSTGRES','SUB-HOU-105','SUB-HOU-0118','Lockwood Substation',29.935119,-95.288563,280.0),
    ('POSTGRES','SUB-HOU-120','SUB-HOU-0119','Louetta Substation',30.045438,-95.480402,270.0),
    ('POSTGRES','SUB-HOU-050','SUB-HOU-0120','Magnolia Park Substation',29.743713,-95.31094,280.0),
    ('POSTGRES','SUB-HOU-147','SUB-HOU-0121','Marine Substation',28.933503,-95.339703,270.0),
    ('POSTGRES','SUB-0032','SUB-HOU-0122','Mary''s Creek Substation',29.554099,-95.257334,85500.0),
    ('POSTGRES','SUB-HOU-051','SUB-HOU-0123','Mason Road Substation',29.745516,-95.739013,270.0),
    ('POSTGRES','SUB-0019','SUB-HOU-0124','Meadow Substation',29.460236,-95.257981,85500.0),
    ('POSTGRES','SUB-HOU-074','SUB-HOU-0125','Memorial Substation',29.789745,-95.61964,270.0),
    ('POSTGRES','SUB-HOU-049','SUB-HOU-0126','Midtown Substation',29.741493,-95.371465,270.0),
    ('POSTGRES','SUB-0048','SUB-HOU-0127','Missouri City Substation',29.612653,-95.530058,111600.0),
    ('POSTGRES','SUB-0017','SUB-HOU-0128','Mustang Bayou Substation',29.362734,-95.203709,111600.0),
    ('POSTGRES','SUB-0012','SUB-HOU-0129','Nash Substation',29.243529,-95.593913,85500.0),
    ('POSTGRES','SUB-HOU-064','SUB-HOU-0130','Normandy Substation',29.769555,-95.205606,270.0),
    ('POSTGRES','SUB-HOU-107','SUB-HOU-0131','North Belt Substation',29.940669,-95.369725,270.0),
    ('POSTGRES','SUB-HOU-070','SUB-HOU-0132','North Side Substation',29.784137,-95.349638,270.0),
    ('POSTGRES','SUB-HOU-169','SUB-HOU-0133','Northeast Houston 1 Substation',30.268055,-95.098712,500.0),
    ('POSTGRES','SUB-HOU-178','SUB-HOU-0134','Northeast Houston 10 Substation',30.299242,-94.929089,300.0),
    ('POSTGRES','SUB-HOU-180','SUB-HOU-0135','Northeast Houston 12 Substation',30.102484,-94.712308,300.0),
    ('POSTGRES','SUB-HOU-141','SUB-HOU-0136','Northeast Houston 141 Substation',30.002928,-95.156625,280.0),
    ('POSTGRES','SUB-HOU-187','SUB-HOU-0137','Northeast Houston 19 Substation',30.270762,-94.707291,150.0),
    ('POSTGRES','SUB-HOU-192','SUB-HOU-0138','Northeast Houston 24 Substation',30.454016,-95.079058,150.0),
    ('POSTGRES','SUB-HOU-171','SUB-HOU-0139','Northeast Houston 3 Substation',30.176318,-95.055571,500.0),
    ('POSTGRES','SUB-HOU-200','SUB-HOU-0140','Northeast Houston 32 Substation',30.454827,-94.916874,150.0),
    ('POSTGRES','SUB-HOU-201','SUB-HOU-0141','Northeast Houston 33 Substation',30.450562,-95.332259,150.0),
    ('POSTGRES','SUB-HOU-207','SUB-HOU-0142','Northeast Houston 39 Substation',30.455755,-94.729933,100.0),
    ('POSTGRES','SUB-HOU-172','SUB-HOU-0143','Northeast Houston 4 Substation',30.301585,-95.306194,500.0),
    ('POSTGRES','SUB-HOU-222','SUB-HOU-0144','Northeast Houston 54 Substation',30.187745,-95.266263,100.0),
    ('POSTGRES','SUB-HOU-224','SUB-HOU-0145','Northeast Houston 56 Substation',30.294914,-94.553864,100.0),
    ('POSTGRES','SUB-HOU-175','SUB-HOU-0146','Northeast Houston 7 Substation',30.088886,-94.900399,300.0),
    ('POSTGRES','SUB-HOU-177','SUB-HOU-0147','Northeast Houston 9 Substation',30.440076,-95.499862,300.0),
    ('POSTGRES','SUB-HOU-179','SUB-HOU-0148','Northwest Houston 11 Substation',30.283495,-95.891023,300.0),
    ('POSTGRES','SUB-HOU-181','SUB-HOU-0149','Northwest Houston 13 Substation',30.1222,-96.317845,300.0),
    ('POSTGRES','SUB-HOU-182','SUB-HOU-0150','Northwest Houston 14 Substation',30.139185,-95.76008,300.0),
    ('POSTGRES','SUB-HOU-183','SUB-HOU-0151','Northwest Houston 15 Substation',30.100034,-96.073022,150.0),
    ('POSTGRES','SUB-HOU-186','SUB-HOU-0152','Northwest Houston 18 Substation',30.322827,-96.095807,150.0),
    ('POSTGRES','SUB-HOU-170','SUB-HOU-0153','Northwest Houston 2 Substation',30.316958,-95.503523,500.0),
    ('POSTGRES','SUB-HOU-190','SUB-HOU-0154','Northwest Houston 22 Substation',30.133385,-96.440996,150.0),
    ('POSTGRES','SUB-HOU-193','SUB-HOU-0155','Northwest Houston 25 Substation',30.430766,-95.683644,150.0),
    ('POSTGRES','SUB-HOU-194','SUB-HOU-0156','Northwest Houston 26 Substation',30.278096,-96.301889,150.0),
    ('POSTGRES','SUB-HOU-208','SUB-HOU-0157','Northwest Houston 40 Substation',30.263298,-96.451819,100.0),
    ('POSTGRES','SUB-HOU-214','SUB-HOU-0158','Northwest Houston 46 Substation',30.452448,-96.08652,100.0),
    ('POSTGRES','SUB-HOU-215','SUB-HOU-0159','Northwest Houston 47 Substation',30.450041,-95.91519,100.0),
    ('POSTGRES','SUB-HOU-173','SUB-HOU-0160','Northwest Houston 5 Substation',30.300132,-95.689732,500.0),
    ('POSTGRES','SUB-HOU-219','SUB-HOU-0161','Northwest Houston 51 Substation',30.447959,-96.460496,100.0),
    ('POSTGRES','SUB-HOU-225','SUB-HOU-0162','Northwest Houston 57 Substation',30.474606,-96.275848,100.0),
    ('POSTGRES','SUB-HOU-174','SUB-HOU-0163','Northwest Houston 6 Substation',30.102567,-95.898036,300.0),
    ('POSTGRES','SUB-HOU-015','SUB-HOU-0164','O''Brien Substation - Northwest',29.673136,-95.717656,270.0),
    ('POSTGRES','SUB-HOU-013','SUB-HOU-0165','O''Brien Substation - Southeast',29.670697,-95.716102,270.0),
    ('POSTGRES','SUB-HOU-069','SUB-HOU-0166','Oates Substation',29.778976,-95.252437,270.0),
    ('POSTGRES','SUB-0025','SUB-HOU-0167','P. H. Robinson Peaker Substation',29.491605,-94.984458,85500.0),
    ('POSTGRES','SUB-0022','SUB-HOU-0168','P. H. Robinson Switching Station',29.487833,-94.982568,111600.0),
    ('POSTGRES','SUB-HOU-082','SUB-HOU-0169','Parkway Substation',29.817955,-95.163556,270.0),
    ('POSTGRES','SUB-HOU-025','SUB-HOU-0170','Pasadena Substation',29.689979,-95.2233,270.0),
    ('POSTGRES','SUB-0033','SUB-HOU-0171','Pearland Substation',29.560127,-95.322661,85500.0),
    ('POSTGRES','SUB-0031','SUB-HOU-0172','Pilgrim Substation',29.552307,-95.174987,111600.0),
    ('POSTGRES','SUB-HOU-022','SUB-HOU-0173','Plaza Substation',29.689432,-95.389563,270.0),
    ('POSTGRES','SUB-0037','SUB-HOU-0174','Polaris Substation',29.578404,-95.09881,85500.0),
    ('POSTGRES','SUB-HOU-058','SUB-HOU-0175','Polk Substation',29.752238,-95.361676,270.0),
    ('POSTGRES','SUB-0039','SUB-HOU-0176','Quail Valley Substation',29.586876,-95.534115,85500.0),
    ('POSTGRES','SUB-HOU-146','SUB-HOU-0177','Quintana Substation',28.932248,-95.317832,270.0),
    ('POSTGRES','SUB-HOU-124','SUB-HOU-0178','Rayford Substation',30.128628,-95.445053,270.0),
    ('POSTGRES','SUB-0036','SUB-HOU-0179','Reading Substation',29.563719,-95.762439,111600.0),
    ('POSTGRES','SUB-0007','SUB-HOU-0180','Retrieve Substation',29.099849,-95.492773,111600.0),
    ('POSTGRES','SUB-HOU-095','SUB-HOU-0181','Rittenhouse Substation',29.863639,-95.379415,280.0),
    ('POSTGRES','SUB-HOU-010','SUB-HOU-0182','Roark Substation',29.666047,-95.56133,270.0),
    ('POSTGRES','SUB-0016','SUB-HOU-0183','Rosharon Substation',29.353714,-95.429661,135000.0),
    ('POSTGRES','SUB-HOU-042','SUB-HOU-0184','S.R. Bertron Plant',29.725098,-95.06029,280.0),
    ('POSTGRES','SUB-HOU-055','SUB-HOU-0185','San Felipe Substation',29.750582,-95.447893,270.0),
    ('POSTGRES','SUB-HOU-018','SUB-HOU-0186','Sandy Point Substation',29.679907,-95.011812,280.0),
    ('POSTGRES','SUB-HOU-097','SUB-HOU-0187','Satsuma Substation',29.881388,-95.576376,270.0),
    ('POSTGRES','SUB-HOU-073','SUB-HOU-0188','Sauer Substation',29.788719,-95.552847,270.0),
    ('POSTGRES','SUB-HOU-098','SUB-HOU-0189','Scenic Woods Substation',29.883723,-95.285265,270.0),
    ('POSTGRES','SUB-HOU-149','SUB-HOU-0190','Seadoc Substation',28.952188,-95.434648,270.0),
    ('POSTGRES','SUB-HOU-148','SUB-HOU-0191','Seaway Substation',28.948821,-95.432726,280.0),
    ('POSTGRES','SUB-HOU-031','SUB-HOU-0192','Sharpstown Substation',29.70139,-95.487266,270.0),
    ('POSTGRES','SUB-0028','SUB-HOU-0193','Sienna Substation',29.538116,-95.561314,111600.0),
    ('POSTGRES','SUB-HOU-164','SUB-HOU-0194','Sintek Substation',28.992286,-95.357386,280.0),
    ('POSTGRES','SUB-HOU-040','SUB-HOU-0195','South Channel Substation',29.721953,-95.164362,280.0),
    ('POSTGRES','SUB-HOU-001','SUB-HOU-0196','South Houston Substation',29.628974,-95.225152,280.0),
    ('POSTGRES','SUB-HOU-086','SUB-HOU-0197','Southeast Houston 086 Substation',29.820021,-95.154083,270.0),
    ('POSTGRES','SUB-HOU-087','SUB-HOU-0198','Southeast Houston 087 Substation',29.820236,-95.126321,270.0),
    ('POSTGRES','SUB-HOU-131','SUB-HOU-0199','Southeast Houston 131 Substation',29.746113,-95.341493,270.0),
    ('POSTGRES','SUB-HOU-150','SUB-HOU-0200','Southeast Houston 150 Substation',28.954247,-95.382441,270.0),
    ('POSTGRES','SUB-HOU-151','SUB-HOU-0201','Southeast Houston 151 Substation',28.955563,-95.382514,270.0),
    ('POSTGRES','SUB-HOU-152','SUB-HOU-0202','Southeast Houston 152 Substation',28.955645,-95.316753,270.0),
    ('POSTGRES','SUB-HOU-155','SUB-HOU-0203','Southeast Houston 155 Substation',28.975879,-95.349997,270.0),
    ('POSTGRES','SUB-HOU-156','SUB-HOU-0204','Southeast Houston 156 Substation',28.978677,-95.341612,280.0),
    ('POSTGRES','SUB-HOU-157','SUB-HOU-0205','Southeast Houston 157 Substation',28.98068,-95.307278,270.0),
    ('POSTGRES','SUB-HOU-158','SUB-HOU-0206','Southeast Houston 158 Substation',28.985058,-95.358243,270.0),
    ('POSTGRES','SUB-HOU-159','SUB-HOU-0207','Southeast Houston 159 Substation',28.985585,-95.393751,270.0),
    ('POSTGRES','SUB-HOU-161','SUB-HOU-0208','Southeast Houston 161 Substation',28.987517,-95.394106,280.0),
    ('POSTGRES','SUB-HOU-163','SUB-HOU-0209','Southeast Houston 163 Substation',28.990503,-95.407443,280.0),
    ('POSTGRES','SUB-HOU-166','SUB-HOU-0210','Southeast Houston 166 Substation',29.003657,-95.405965,270.0),
    ('POSTGRES','SUB-HOU-188','SUB-HOU-0211','Southeast Houston 20 Substation',29.891608,-94.69053,150.0),
    ('POSTGRES','SUB-HOU-196','SUB-HOU-0212','Southeast Houston 28 Substation',29.902033,-94.839751,150.0),
    ('POSTGRES','SUB-HOU-198','SUB-HOU-0213','Southeast Houston 30 Substation',29.452197,-94.661552,150.0),
    ('POSTGRES','SUB-HOU-209','SUB-HOU-0214','Southeast Houston 41 Substation',29.733711,-94.666488,100.0),
    ('POSTGRES','SUB-HOU-221','SUB-HOU-0215','Southeast Houston 53 Substation',29.486075,-94.560483,100.0),
    ('POSTGRES','SUB-HOU-226','SUB-HOU-0216','Southeast Houston 58 Substation',29.898586,-94.561728,100.0),
    ('POSTGRES','SUB-HOU-184','SUB-HOU-0217','Southwest Houston 16 Substation',29.312339,-96.086544,150.0),
    ('POSTGRES','SUB-HOU-185','SUB-HOU-0218','Southwest Houston 17 Substation',29.724393,-96.103091,150.0),
    ('POSTGRES','SUB-HOU-189','SUB-HOU-0219','Southwest Houston 21 Substation',29.9003,-96.083521,150.0),
    ('POSTGRES','SUB-HOU-191','SUB-HOU-0220','Southwest Houston 23 Substation',28.940567,-95.93764,150.0),
    ('POSTGRES','SUB-HOU-195','SUB-HOU-0221','Southwest Houston 27 Substation',29.918006,-96.29295,150.0),
    ('POSTGRES','SUB-HOU-197','SUB-HOU-0222','Southwest Houston 29 Substation',29.503478,-96.071844,150.0),
    ('POSTGRES','SUB-HOU-199','SUB-HOU-0223','Southwest Houston 31 Substation',29.275077,-96.290417,150.0),
    ('POSTGRES','SUB-HOU-202','SUB-HOU-0224','Southwest Houston 34 Substation',29.141507,-96.278278,150.0),
    ('POSTGRES','SUB-HOU-203','SUB-HOU-0225','Southwest Houston 35 Substation',29.30501,-95.926592,100.0),
    ('POSTGRES','SUB-HOU-204','SUB-HOU-0226','Southwest Houston 36 Substation',29.895936,-95.963496,100.0),
    ('POSTGRES','SUB-HOU-205','SUB-HOU-0227','Southwest Houston 37 Substation',29.06646,-95.890251,100.0),
    ('POSTGRES','SUB-HOU-206','SUB-HOU-0228','Southwest Houston 38 Substation',29.488459,-95.940356,100.0),
    ('POSTGRES','SUB-HOU-210','SUB-HOU-0229','Southwest Houston 42 Substation',29.522501,-96.322569,100.0),
    ('POSTGRES','SUB-HOU-211','SUB-HOU-0230','Southwest Houston 43 Substation',28.90416,-96.127199,100.0),
    ('POSTGRES','SUB-HOU-212','SUB-HOU-0231','Southwest Houston 44 Substation',29.738362,-96.300115,100.0),
    ('POSTGRES','SUB-HOU-213','SUB-HOU-0232','Southwest Houston 45 Substation',29.907038,-96.459919,100.0),
    ('POSTGRES','SUB-HOU-216','SUB-HOU-0233','Southwest Houston 48 Substation',28.72988,-96.259037,100.0),
    ('POSTGRES','SUB-HOU-217','SUB-HOU-0234','Southwest Houston 49 Substation',28.779485,-95.647781,100.0),
    ('POSTGRES','SUB-HOU-218','SUB-HOU-0235','Southwest Houston 50 Substation',29.715989,-96.443063,100.0),
    ('POSTGRES','SUB-HOU-220','SUB-HOU-0236','Southwest Houston 52 Substation',28.89087,-96.244847,100.0),
    ('POSTGRES','SUB-HOU-223','SUB-HOU-0237','Southwest Houston 55 Substation',28.891471,-95.705817,100.0),
    ('POSTGRES','SUB-HOU-176','SUB-HOU-0238','Southwest Houston 8 Substation',29.71316,-95.9253,300.0),
    ('POSTGRES','SUB-0030','SUB-HOU-0239','Southwyck Substation',29.552252,-95.389281,85500.0),
    ('POSTGRES','SUB-HOU-007','SUB-HOU-0240','Spencer Substation',29.657841,-95.190766,270.0),
    ('POSTGRES','SUB-HOU-122','SUB-HOU-0241','Springwood Substation',30.086204,-95.440382,280.0),
    ('POSTGRES','SUB-HOU-020','SUB-HOU-0242','Stadium Substation',29.685297,-95.406514,280.0),
    ('POSTGRES','SUB-HOU-003','SUB-HOU-0243','Stafford Substation',29.633727,-95.58919,270.0),
    ('POSTGRES','SUB-0011','SUB-HOU-0244','Stewart Substation',29.227786,-94.910684,85500.0),
    ('POSTGRES','SUB-HOU-029','SUB-HOU-0245','Strawberry Belt Substation',29.699147,-95.172032,270.0),
    ('POSTGRES','SUB-HOU-153','SUB-HOU-0246','Surfside Substation',28.958795,-95.339157,270.0),
    ('POSTGRES','SUB-HOU-106','SUB-HOU-0247','T. H. Wharton Substation',29.939627,-95.533086,280.0),
    ('POSTGRES','SUB-0043','SUB-HOU-0248','Telephone Substation',29.59913,-95.287396,85500.0),
    ('POSTGRES','SUB-0038','SUB-HOU-0249','Telview Substation',29.579432,-95.487489,85500.0),
    ('POSTGRES','SUB-HOU-125','SUB-HOU-0250','Texas Pipeline Substation',29.145796,-95.674662,280.0),
    ('POSTGRES','SUB-0020','SUB-HOU-0251','Thompsons Substation',29.481245,-95.586379,111600.0),
    ('POSTGRES','SUB-0014','SUB-HOU-0252','Tiki Island Substation',29.304148,-94.90105,150000.0),
    ('POSTGRES','SUB-HOU-081','SUB-HOU-0253','Todd Substation',29.816018,-95.483023,270.0),
    ('POSTGRES','SUB-HOU-123','SUB-HOU-0254','Tomball Substation',30.090101,-95.606029,280.0),
    ('POSTGRES','SUB-HOU-119','SUB-HOU-0255','Treaschwig Substation',30.0439,-95.350887,270.0),
    ('POSTGRES','SUB-HOU-038','SUB-HOU-0256','Trinity Bay Substation - Northwest',29.719546,-94.914629,280.0),
    ('POSTGRES','SUB-HOU-021','SUB-HOU-0257','Trinity Bay Substation - Southeast',29.68923,-94.911634,270.0),
    ('POSTGRES','SUB-HOU-047','SUB-HOU-0258','Ulrich Substation',29.735881,-95.483811,280.0),
    ('POSTGRES','SUB-HOU-026','SUB-HOU-0259','Underwood Substation',29.692,-95.089056,270.0),
    ('POSTGRES','SUB-HOU-036','SUB-HOU-0260','University Substation',29.716822,-95.331412,270.0),
    ('POSTGRES','SUB-0003','SUB-HOU-0261','Velasco Substation',28.980227,-95.362655,112500.0),
    ('POSTGRES','SUB-0021','SUB-HOU-0262','W. A. Parish Station (138 kV)',29.482804,-95.630275,85500.0),
    ('POSTGRES','SUB-HOU-129','SUB-HOU-0263','W. A. Parish Station (345 kV)',29.480777,-95.624219,270.0),
    ('POSTGRES','SUB-HOU-136','SUB-HOU-0264','Wallisville Substation',29.787463,-95.291255,280.0),
    ('POSTGRES','SUB-0027','SUB-HOU-0265','Webster Substation',29.528341,-95.104951,85500.0),
    ('POSTGRES','SUB-0009','SUB-HOU-0266','West Columbia Substation',29.156791,-95.657564,85500.0),
    ('POSTGRES','SUB-0008','SUB-HOU-0267','Westbay Substation',29.112682,-95.09062,111600.0),
    ('POSTGRES','SUB-HOU-117','SUB-HOU-0268','Westfield Substation',30.020638,-95.42209,280.0),
    ('POSTGRES','SUB-HOU-048','SUB-HOU-0269','Westheimer Substation',29.736607,-95.617304,270.0),
    ('POSTGRES','SUB-HOU-024','SUB-HOU-0270','Westwood Substation',29.689947,-95.536681,280.0),
    ('POSTGRES','SUB-HOU-080','SUB-HOU-0271','White Oak Substation',29.815179,-95.434815,280.0),
    ('POSTGRES','SUB-HOU-114','SUB-HOU-0272','Willow Substation',29.996873,-95.566539,280.0),
    ('POSTGRES','SUB-HOU-071','SUB-HOU-0273','Wirt Substation',29.785233,-95.479623,280.0),
    ('POSTGRES','SUB-HOU-035','SUB-HOU-0274','Witter Substation',29.716243,-95.200506,270.0),
    ('POSTGRES','SUB-HOU-101','SUB-HOU-0275','Zenith Substation',29.910066,-95.777189,280.0);


-- ---------------------------------------------------------------------------
-- PHASE 1 -- SUBSTATIONS (275, real names/coords, canonical 4-digit keys)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE SUBSTATIONS AS
SELECT
    x.CANONICAL_ID                                          AS SUBSTATION_ID,
    x.SUBSTATION_NAME                                       AS SUBSTATION_NAME,
    x.LATITUDE                                              AS LATITUDE,
    x.LONGITUDE                                             AS LONGITUDE,
    x.CAPACITY_MVA                                          AS CAPACITY_MVA,
    CASE UNIFORM(0,2,HASH(x.CANONICAL_ID,'vclass'))
         WHEN 0 THEN '138KV' WHEN 1 THEN '69KV' ELSE '345KV' END AS VOLTAGE_CLASS,
    'HOUSTON_METRO'                                         AS REGION,
    'ACTIVE'                                                AS OPERATIONAL_STATUS,
    DATEADD('day', -UNIFORM(3650,18250,HASH(x.CANONICAL_ID,'commission')), CURRENT_DATE()) AS COMMISSIONED_DATE,
    DATEADD('day', -UNIFORM(1,365,HASH(x.CANONICAL_ID,'inspect')),  CURRENT_DATE())        AS LAST_INSPECTION_DATE,
    -- load is now POPULATED (was NULL for every row before)
    ROUND(x.CAPACITY_MVA * UNIFORM(0.35::FLOAT,0.78::FLOAT,HASH(x.CANONICAL_ID,'load')), 2) AS CURRENT_LOAD_MW,
    ROUND(x.CAPACITY_MVA * UNIFORM(0.80::FLOAT,0.95::FLOAT,HASH(x.CANONICAL_ID,'peak')), 2) AS PEAK_LOAD_MW,
    ROUND(100 * UNIFORM(0.35::FLOAT,0.78::FLOAT,HASH(x.CANONICAL_ID,'load')), 2)            AS LOAD_FACTOR_PCT
FROM SUBSTATION_ID_XREF x
WHERE x.SOURCE_SYSTEM = 'POSTGRES';

-- ---------------------------------------------------------------------------
-- PHASE 2 -- CIRCUIT_METADATA (feeders): 20-45 per substation
-- REPRESENTATIVE_LAT/LON is the feeder's representative POINT. A real feeder is
-- a LINE, so these columns are deliberately NOT named LATITUDE/LONGITUDE and
-- are never mistaken for feeder geometry. R = 5.5 km from the substation.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE CIRCUIT_METADATA AS
WITH nums AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 45))),
expanded AS (
    SELECT s.SUBSTATION_ID, s.SUBSTATION_NAME, s.LATITUDE AS S_LAT, s.LONGITUDE AS S_LON,
           n.n + 1 AS SEQ,
           s.SUBSTATION_ID || '-' || LPAD((n.n + 1)::VARCHAR, 2, '0') AS SUFFIX
    FROM SUBSTATIONS s
    CROSS JOIN nums n
    WHERE n.n < UNIFORM(20, 45, HASH(s.SUBSTATION_ID, 'ncirc'))
),
placed AS (
    SELECT e.*,
           'FEEDER-' || e.SUFFIX AS CIRCUIT_ID,
           5.5 * SQRT(UNIFORM(0::FLOAT,1::FLOAT,HASH('FEEDER-'||e.SUFFIX,'radius')))  AS D_KM,
           2*PI() * UNIFORM(0::FLOAT,1::FLOAT,HASH('FEEDER-'||e.SUFFIX,'bearing'))    AS BRG
    FROM expanded e
)
SELECT
    p.CIRCUIT_ID                                            AS CIRCUIT_ID,
    REPLACE(p.SUBSTATION_NAME,' Substation','') || ' Feeder ' || LPAD(p.SEQ::VARCHAR,2,'0') AS CIRCUIT_NAME,
    p.SUBSTATION_ID                                         AS SUBSTATION_ID,
    CASE UNIFORM(0,2,HASH(p.CIRCUIT_ID,'vclass'))
         WHEN 0 THEN '12KV' WHEN 1 THEN '25KV' ELSE '4KV' END AS VOLTAGE_CLASS,
    ROUND(UNIFORM(1.5::FLOAT,9.5::FLOAT,HASH(p.CIRCUIT_ID,'len')), 2) AS LENGTH_MILES,
    CASE UNIFORM(0,3,HASH(p.CIRCUIT_ID,'cond'))
         WHEN 0 THEN 'ACSR 336' WHEN 1 THEN 'ACSR 795'
         WHEN 2 THEN 'AL 1/0'   ELSE 'CU 4/0' END           AS CONDUCTOR_TYPE,
    CASE WHEN UNIFORM(0::FLOAT,1::FLOAT,HASH(p.CIRCUIT_ID,'status')) < 0.985
         THEN 'ENERGIZED' ELSE 'OUTAGE' END                 AS STATUS,
    0::NUMBER(38,0)                                         AS CUSTOMER_COUNT,  -- backfilled in PHASE 6
    ROUND(p.S_LAT + (p.D_KM * COS(p.BRG))
          / (111.132 - 0.559*COS(2*RADIANS(p.S_LAT)) + 0.001*COS(4*RADIANS(p.S_LAT))), 6) AS REPRESENTATIVE_LAT,
    ROUND(p.S_LON + (p.D_KM * SIN(p.BRG))
          / (111.320 * COS(RADIANS(p.S_LAT))), 6)                                          AS REPRESENTATIVE_LON
FROM placed p;


-- ---------------------------------------------------------------------------
-- PHASE 3 -- TRANSFORMER_METADATA: 3-20 per feeder, placed within R = 4.0 km
-- of their FEEDER's representative point (not the substation). Composing the
-- 5.5 km feeder offset with the 4.0 km transformer offset yields a
-- transformer->substation mean of ~sqrt(3.67^2 + 2.67^2) ~= 4.5 km, matching
-- the January audit mean of 4527 m, with a hard ceiling of 9.5 km (gate: 15 km).
-- Adds CIRCUIT_ID (the live table had none) and H3_INDEX_RES9 for proximity work.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE TRANSFORMER_METADATA AS
WITH nums AS (SELECT SEQ4() AS n FROM TABLE(GENERATOR(ROWCOUNT => 20))),
expanded AS (
    SELECT c.CIRCUIT_ID, c.SUBSTATION_ID, c.CIRCUIT_NAME,
           c.REPRESENTATIVE_LAT AS C_LAT, c.REPRESENTATIVE_LON AS C_LON,
           n.n + 1 AS SEQ
    FROM CIRCUIT_METADATA c
    CROSS JOIN nums n
    WHERE n.n < UNIFORM(3, 20, HASH(c.CIRCUIT_ID, 'nxfmr'))
),
keyed AS (
    SELECT e.*,
           'XFMR-HOU-' || LPAD(ROW_NUMBER() OVER (ORDER BY e.CIRCUIT_ID, e.SEQ)::VARCHAR, 6, '0') AS TRANSFORMER_ID
    FROM expanded e
),
attrs AS (
    SELECT k.*,
           4.0 * SQRT(UNIFORM(0::FLOAT,1::FLOAT,HASH(k.TRANSFORMER_ID,'radius'))) AS D_KM,
           2*PI() * UNIFORM(0::FLOAT,1::FLOAT,HASH(k.TRANSFORMER_ID,'bearing'))   AS BRG,
           CASE UNIFORM(0,11,HASH(k.TRANSFORMER_ID,'kva'))
                WHEN 0 THEN 15 WHEN 1 THEN 25 WHEN 2 THEN 37.5 WHEN 3 THEN 50
                WHEN 4 THEN 75 WHEN 5 THEN 100 WHEN 6 THEN 167 WHEN 7 THEN 250
                WHEN 8 THEN 333 WHEN 9 THEN 500 WHEN 10 THEN 750 ELSE 1000
           END AS CAPACITY_KVA,
           ROUND(UNIFORM(28::FLOAT,99::FLOAT,HASH(k.TRANSFORMER_ID,'health')), 1) AS HEALTH_SCORE,
           UNIFORM(0.30::FLOAT,0.92::FLOAT,HASH(k.TRANSFORMER_ID,'load'))        AS LOAD_FRAC
    FROM keyed k
),
geo AS (
    SELECT a.*,
           ROUND(a.C_LAT + (a.D_KM * COS(a.BRG))
                 / (111.132 - 0.559*COS(2*RADIANS(a.C_LAT)) + 0.001*COS(4*RADIANS(a.C_LAT))), 6) AS LAT,
           ROUND(a.C_LON + (a.D_KM * SIN(a.BRG))
                 / (111.320 * COS(RADIANS(a.C_LAT))), 6)                                          AS LON
    FROM attrs a
)
SELECT
    g.TRANSFORMER_ID,
    'XFMR ' || g.CIRCUIT_NAME || ' #' || LPAD(g.SEQ::VARCHAR,2,'0') AS TRANSFORMER_NAME,
    g.SUBSTATION_ID,
    g.CIRCUIT_ID,
    g.LAT AS LATITUDE,
    g.LON AS LONGITUDE,
    g.CAPACITY_KVA,
    CASE UNIFORM(0,4,HASH(g.TRANSFORMER_ID,'pv'))
         WHEN 0 THEN 4.16 WHEN 1 THEN 12.47 WHEN 2 THEN 13.2
         WHEN 3 THEN 13.8 ELSE 24.94 END                    AS PRIMARY_VOLTAGE_KV,
    0.24                                                    AS SECONDARY_VOLTAGE_KV,
    UNIFORM(1972, 2025, HASH(g.TRANSFORMER_ID,'year'))      AS INSTALL_YEAR,
    CASE UNIFORM(0,8,HASH(g.TRANSFORMER_ID,'mfr'))
         WHEN 0 THEN 'ABB' WHEN 1 THEN 'Siemens' WHEN 2 THEN 'GE'
         WHEN 3 THEN 'Eaton' WHEN 4 THEN 'Schneider Electric'
         WHEN 5 THEN 'Howard Industries' WHEN 6 THEN 'Cooper Power'
         WHEN 7 THEN 'Hitachi' ELSE 'Toshiba' END           AS MANUFACTURER,
    'MOD-' || LPAD(UNIFORM(1000,9999,HASH(g.TRANSFORMER_ID,'model'))::VARCHAR,4,'0') AS MODEL,
    DATEADD('day', -UNIFORM(1,1095,HASH(g.TRANSFORMER_ID,'maint')), CURRENT_DATE()) AS LAST_MAINTENANCE_DATE,
    ROUND(g.CAPACITY_KVA * g.LOAD_FRAC, 1)                  AS CURRENT_LOAD_KVA,
    g.HEALTH_SCORE,
    CASE WHEN g.HEALTH_SCORE < 40 THEN 'CRITICAL'
         WHEN g.HEALTH_SCORE < 60 THEN 'HIGH'
         WHEN g.HEALTH_SCORE < 80 THEN 'MEDIUM'
         ELSE 'LOW' END                                     AS RISK_CATEGORY,
    H3_LATLNG_TO_CELL_STRING(g.LAT, g.LON, 9)               AS H3_INDEX_RES9
FROM geo g;

-- ---------------------------------------------------------------------------
-- PHASE 4 -- GRID_POLES_INFRASTRUCTURE: ~68% of transformers are pole-mounted
-- (audit: 62,038 poles vs 90,951 transformers). R = 0.32 km. Gate: 500 m.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE GRID_POLES_INFRASTRUCTURE AS
WITH picked AS (
    SELECT t.TRANSFORMER_ID, t.SUBSTATION_ID, t.CIRCUIT_ID,
           t.LATITUDE AS T_LAT, t.LONGITUDE AS T_LON,
           'POLE-HOU-' || LPAD(ROW_NUMBER() OVER (ORDER BY t.TRANSFORMER_ID)::VARCHAR, 6, '0') AS POLE_ID
    FROM TRANSFORMER_METADATA t
    WHERE UNIFORM(0::FLOAT,1::FLOAT,HASH(t.TRANSFORMER_ID,'haspole')) < 0.68
),
placed AS (
    SELECT p.*,
           0.32 * SQRT(UNIFORM(0::FLOAT,1::FLOAT,HASH(p.POLE_ID,'radius'))) AS D_KM,
           2*PI() * UNIFORM(0::FLOAT,1::FLOAT,HASH(p.POLE_ID,'bearing'))    AS BRG
    FROM picked p
)
SELECT
    p.POLE_ID, p.TRANSFORMER_ID, p.SUBSTATION_ID, p.CIRCUIT_ID,
    ROUND(p.T_LAT + (p.D_KM * COS(p.BRG))
          / (111.132 - 0.559*COS(2*RADIANS(p.T_LAT)) + 0.001*COS(4*RADIANS(p.T_LAT))), 6) AS LATITUDE,
    ROUND(p.T_LON + (p.D_KM * SIN(p.BRG))
          / (111.320 * COS(RADIANS(p.T_LAT))), 6)                                          AS LONGITUDE,
    UNIFORM(30,55,HASH(p.POLE_ID,'height'))                 AS POLE_HEIGHT_FT,
    CASE UNIFORM(0,2,HASH(p.POLE_ID,'mat'))
         WHEN 0 THEN 'WOOD' WHEN 1 THEN 'STEEL' ELSE 'CONCRETE' END AS POLE_MATERIAL,
    'CLASS-' || UNIFORM(1,5,HASH(p.POLE_ID,'class'))::VARCHAR AS POLE_CLASS,
    ROUND(UNIFORM(30::FLOAT,99::FLOAT,HASH(p.POLE_ID,'health')),1) AS HEALTH_SCORE,
    CASE WHEN UNIFORM(30::FLOAT,99::FLOAT,HASH(p.POLE_ID,'health')) < 45 THEN 'POOR'
         WHEN UNIFORM(30::FLOAT,99::FLOAT,HASH(p.POLE_ID,'health')) < 70 THEN 'FAIR'
         ELSE 'GOOD' END                                     AS CONDITION_STATUS,
    CURRENT_TIMESTAMP()                                      AS CREATED_AT
FROM placed p;


-- ---------------------------------------------------------------------------
-- PHASE 5 -- METER_INFRASTRUCTURE RE-LINK  (METER_ID IS PRESERVED)
-- 288,000,000 AMI rows are keyed by METER_ID, so meters are re-parented and
-- moved, never re-keyed. Each meter is bound to a pole-mounted transformer and
-- placed within R = 0.36 km of its pole (audit service-drop mean 241 m).
--
-- Reads the meter identity columns from the PRE-REGEN ZERO-COPY CLONE rather
-- than from METER_INFRASTRUCTURE itself, so the source is unambiguous while the
-- target is being replaced.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE METER_INFRASTRUCTURE AS
WITH poles AS (
    SELECT POLE_ID, TRANSFORMER_ID, SUBSTATION_ID, CIRCUIT_ID,
           LATITUDE AS P_LAT, LONGITUDE AS P_LON,
           ROW_NUMBER() OVER (ORDER BY POLE_ID) - 1 AS RN
    FROM GRID_POLES_INFRASTRUCTURE
),
pole_count AS (SELECT COUNT(*) AS N_POLES FROM poles),
old AS (
    SELECT m.METER_ID, m.METER_NUMBER, m.METER_TYPE, m.INSTALL_DATE, m.STATUS,
           m.CUSTOMER_CLASS, m.HEALTH_SCORE, m.COUNTY_NAME, m.CITY,
           -- deterministic pole assignment from the meter's own immutable key.
           -- FLOOR(uniform * N) -- never ABS(HASH(x)) % N, since ABS(-2^63) overflows negative.
           FLOOR(UNIFORM(0::FLOAT, 1::FLOAT, HASH(m.METER_ID, 'pole')) * pc.N_POLES) AS POLE_RN
    FROM PRODUCTION_PREREGEN_20260729.METER_INFRASTRUCTURE m
    CROSS JOIN pole_count pc
),
joined AS (
    SELECT o.*, p.POLE_ID, p.TRANSFORMER_ID, p.SUBSTATION_ID, p.CIRCUIT_ID, p.P_LAT, p.P_LON
    FROM old o JOIN poles p ON p.RN = o.POLE_RN
),
placed AS (
    SELECT j.*,
           0.36 * SQRT(UNIFORM(0::FLOAT,1::FLOAT,HASH(j.METER_ID,'radius'))) AS D_KM,
           2*PI() * UNIFORM(0::FLOAT,1::FLOAT,HASH(j.METER_ID,'bearing'))    AS BRG
    FROM joined j
),
geo AS (
    SELECT p.*,
           ROUND(p.P_LAT + (p.D_KM * COS(p.BRG))
                 / (111.132 - 0.559*COS(2*RADIANS(p.P_LAT)) + 0.001*COS(4*RADIANS(p.P_LAT))), 6) AS LAT,
           ROUND(p.P_LON + (p.D_KM * SIN(p.BRG))
                 / (111.320 * COS(RADIANS(p.P_LAT))), 6)                                          AS LON
    FROM placed p
)
SELECT
    g.METER_ID, g.METER_NUMBER,
    g.TRANSFORMER_ID, g.CIRCUIT_ID, g.POLE_ID,
    g.LAT AS LATITUDE, g.LON AS LONGITUDE,
    g.LAT AS METER_LATITUDE, g.LON AS METER_LONGITUDE,
    g.METER_TYPE, g.INSTALL_DATE, g.STATUS, g.CUSTOMER_CLASS,
    g.HEALTH_SCORE, g.COUNTY_NAME, g.CITY,
    H3_LATLNG_TO_CELL_STRING(g.LAT, g.LON, 9) AS H3_INDEX_RES9
FROM geo g;

-- ---------------------------------------------------------------------------
-- PHASE 6 -- Backfill CUSTOMER_COUNT on feeders from the re-linked meters
-- ---------------------------------------------------------------------------
UPDATE CIRCUIT_METADATA c
SET CUSTOMER_COUNT = COALESCE(m.CNT, 0)
FROM (SELECT CIRCUIT_ID, COUNT(*) AS CNT FROM METER_INFRASTRUCTURE GROUP BY CIRCUIT_ID) m
WHERE c.CIRCUIT_ID = m.CIRCUIT_ID;
