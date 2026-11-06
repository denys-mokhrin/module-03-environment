export function health(uptimeSeconds: number): { status: 'ok'; uptime: number } {
  return { status: 'ok', uptime: Math.round(uptimeSeconds) };
}
