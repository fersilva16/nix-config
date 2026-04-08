import type { Plugin } from "@opencode-ai/plugin"
import { writeFileSync, readFileSync, mkdirSync, existsSync } from "fs"

const MAPPING_DIR = "/tmp/opencode-pane-sessions"
const PANE_ID = process.env.TMUX_PANE ?? ""
const CLEAN_ID = PANE_ID.replace(/%/g, "")
const MAPPING_FILE = `${MAPPING_DIR}/${CLEAN_ID}`

function filterTitle(title: string): string {
  if (!title || title.startsWith("<") || title.startsWith("{")) return ""
  return title
}

function writeMapping(sessionID: string, title: string, status: string) {
  const tmp = `${MAPPING_FILE}.tmp`
  writeFileSync(tmp, JSON.stringify({ sessionID, title, status }) + "\n")
  const { renameSync } = require("fs")
  renameSync(tmp, MAPPING_FILE)
}

function readMapping(): { sessionID: string; title: string; status: string } | null {
  try {
    return JSON.parse(readFileSync(MAPPING_FILE, "utf-8").trim())
  } catch {
    return null
  }
}

export const PaneMappingPlugin: Plugin = async ({ client }) => {
  if (!PANE_ID) return {}

  mkdirSync(MAPPING_DIR, { recursive: true })

  // Seed from the most recently updated session for this directory
  try {
    const { data: sessions } = await client.session.list()
    const match = sessions?.find((s) => s.directory === directory)
    if (match) {
      writeMapping(match.id, filterTitle(match.title), "idle")
    }
  } catch {}

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.status": {
          const { sessionID, status } = event.properties
          if (status.type === "busy") {
            let title = ""
            try {
              const { data } = await client.session.get({ path: { id: sessionID } })
              if (data) title = filterTitle(data.title)
            } catch {}
            writeMapping(sessionID, title, "busy")
          } else if (status.type === "idle") {
            const m = readMapping()
            if (m?.sessionID === sessionID) writeMapping(sessionID, m.title, "idle")
          }
          break
        }

        case "session.updated": {
          const { info } = event.properties
          const m = readMapping()
          if (m?.sessionID === info.id) {
            writeMapping(info.id, filterTitle(info.title), m.status)
          }
          break
        }

        case "session.created": {
          writeMapping(event.properties.info.id, filterTitle(event.properties.info.title), "idle")
          break
        }
      }
    },
  }
}
