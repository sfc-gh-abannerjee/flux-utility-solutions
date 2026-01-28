/**
 * Flux Ops Center - Main Application Component
 * 
 * Features:
 * - DeckGL map with grid infrastructure layers
 * - Real-time stats dashboard
 * - Cortex AI chat assistant
 * - Responsive layout for operations center displays
 */

import { useState, useEffect, useCallback } from 'react'
import { Box, Paper, Typography, Chip, IconButton, Drawer, TextField, Button, CircularProgress } from '@mui/material'
import ChatIcon from '@mui/icons-material/Chat'
import SendIcon from '@mui/icons-material/Send'
import CloseIcon from '@mui/icons-material/Close'
import Map, { NavigationControl } from 'react-map-gl/maplibre'
import DeckGL from '@deck.gl/react'
import { ScatterplotLayer, IconLayer, PathLayer } from '@deck.gl/layers'
import 'maplibre-gl/dist/maplibre-gl.css'

// Types
interface GridStats {
  substations: number
  transformers: number
  customers: number
  meters: number
  active_outages: number
}

interface Substation {
  substation_id: string
  name: string
  longitude: number
  latitude: number
  capacity_mva: number
  status: string
}

interface ChatMessage {
  role: 'user' | 'assistant'
  content: string
}

// Initial map view (Houston area)
const INITIAL_VIEW_STATE = {
  longitude: -95.37,
  latitude: 29.76,
  zoom: 10,
  pitch: 45,
  bearing: 0,
}

// Map style (CartoDB dark matter - free, no API key)
const MAP_STYLE = 'https://basemaps.cartocdn.com/gl/dark-matter-gl-style/style.json'

export default function App() {
  // State
  const [viewState, setViewState] = useState(INITIAL_VIEW_STATE)
  const [stats, setStats] = useState<GridStats | null>(null)
  const [substations, setSubstations] = useState<Substation[]>([])
  const [chatOpen, setChatOpen] = useState(false)
  const [chatMessages, setChatMessages] = useState<ChatMessage[]>([])
  const [chatInput, setChatInput] = useState('')
  const [chatLoading, setChatLoading] = useState(false)

  // Fetch grid statistics
  useEffect(() => {
    fetch('/api/grid/stats')
      .then(res => res.json())
      .then(setStats)
      .catch(console.error)
  }, [])

  // Fetch substations
  useEffect(() => {
    fetch('/api/grid/substations')
      .then(res => res.json())
      .then(setSubstations)
      .catch(console.error)
  }, [])

  // Send chat message to Cortex Agent
  const sendMessage = useCallback(async () => {
    if (!chatInput.trim() || chatLoading) return

    const userMessage = chatInput.trim()
    setChatInput('')
    setChatMessages(prev => [...prev, { role: 'user', content: userMessage }])
    setChatLoading(true)

    try {
      const response = await fetch('/api/agent/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: userMessage }),
      })

      const reader = response.body?.getReader()
      const decoder = new TextDecoder()
      let assistantMessage = ''

      if (reader) {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break

          const chunk = decoder.decode(value)
          const lines = chunk.split('\n')

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              try {
                const data = JSON.parse(line.slice(6))
                if (data.type === 'text') {
                  assistantMessage += data.content
                }
              } catch {}
            }
          }
        }
      }

      setChatMessages(prev => [...prev, { role: 'assistant', content: assistantMessage }])
    } catch (error) {
      setChatMessages(prev => [...prev, { role: 'assistant', content: 'Error connecting to agent.' }])
    } finally {
      setChatLoading(false)
    }
  }, [chatInput, chatLoading])

  // DeckGL layers
  const layers = [
    // Substations as colored circles
    new ScatterplotLayer({
      id: 'substations',
      data: substations,
      getPosition: (d: Substation) => [d.longitude, d.latitude],
      getRadius: (d: Substation) => Math.sqrt(d.capacity_mva) * 100,
      getFillColor: (d: Substation) => 
        d.status === 'ACTIVE' ? [79, 195, 247, 200] : [244, 67, 54, 200],
      pickable: true,
      radiusMinPixels: 8,
      radiusMaxPixels: 50,
    }),
  ]

  return (
    <Box sx={{ width: '100vw', height: '100vh', position: 'relative' }}>
      {/* Map with DeckGL overlay */}
      <DeckGL
        viewState={viewState}
        onViewStateChange={({ viewState }) => setViewState(viewState as any)}
        controller={true}
        layers={layers}
      >
        <Map mapStyle={MAP_STYLE}>
          <NavigationControl position="top-right" />
        </Map>
      </DeckGL>

      {/* Stats Dashboard */}
      <Paper
        sx={{
          position: 'absolute',
          top: 16,
          left: 16,
          p: 2,
          minWidth: 280,
          backgroundColor: 'rgba(26, 26, 46, 0.9)',
          backdropFilter: 'blur(8px)',
        }}
      >
        <Typography variant="h6" sx={{ mb: 2, color: 'primary.main' }}>
          Flux Grid Status
        </Typography>
        
        {stats ? (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <StatRow label="Substations" value={stats.substations} />
            <StatRow label="Transformers" value={stats.transformers.toLocaleString()} />
            <StatRow label="Customers" value={stats.customers.toLocaleString()} />
            <StatRow label="Meters" value={stats.meters.toLocaleString()} />
            <Box sx={{ mt: 1 }}>
              <Chip
                label={`${stats.active_outages} Active Outages`}
                color={stats.active_outages > 0 ? 'error' : 'success'}
                size="small"
              />
            </Box>
          </Box>
        ) : (
          <CircularProgress size={24} />
        )}
      </Paper>

      {/* Chat FAB */}
      <IconButton
        onClick={() => setChatOpen(true)}
        sx={{
          position: 'absolute',
          bottom: 24,
          right: 24,
          backgroundColor: 'primary.main',
          color: 'black',
          width: 56,
          height: 56,
          '&:hover': { backgroundColor: 'primary.light' },
        }}
      >
        <ChatIcon />
      </IconButton>

      {/* Chat Drawer */}
      <Drawer
        anchor="right"
        open={chatOpen}
        onClose={() => setChatOpen(false)}
        PaperProps={{
          sx: { width: 400, backgroundColor: 'background.paper' },
        }}
      >
        <Box sx={{ p: 2, borderBottom: 1, borderColor: 'divider', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Typography variant="h6">Cortex AI Assistant</Typography>
          <IconButton onClick={() => setChatOpen(false)}>
            <CloseIcon />
          </IconButton>
        </Box>

        {/* Messages */}
        <Box sx={{ flex: 1, overflow: 'auto', p: 2 }}>
          {chatMessages.map((msg, i) => (
            <Box
              key={i}
              sx={{
                mb: 2,
                p: 1.5,
                borderRadius: 2,
                backgroundColor: msg.role === 'user' ? 'primary.dark' : 'grey.800',
                ml: msg.role === 'user' ? 4 : 0,
                mr: msg.role === 'assistant' ? 4 : 0,
              }}
            >
              <Typography variant="body2">{msg.content}</Typography>
            </Box>
          ))}
          {chatLoading && (
            <Box sx={{ display: 'flex', justifyContent: 'center', p: 2 }}>
              <CircularProgress size={24} />
            </Box>
          )}
        </Box>

        {/* Input */}
        <Box sx={{ p: 2, borderTop: 1, borderColor: 'divider', display: 'flex', gap: 1 }}>
          <TextField
            fullWidth
            size="small"
            placeholder="Ask about the grid..."
            value={chatInput}
            onChange={(e) => setChatInput(e.target.value)}
            onKeyPress={(e) => e.key === 'Enter' && sendMessage()}
          />
          <Button variant="contained" onClick={sendMessage} disabled={chatLoading}>
            <SendIcon />
          </Button>
        </Box>
      </Drawer>
    </Box>
  )
}

// Helper component for stats
function StatRow({ label, value }: { label: string; value: string | number }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
      <Typography variant="body2" color="text.secondary">{label}</Typography>
      <Typography variant="body2" fontWeight={600}>{value}</Typography>
    </Box>
  )
}
