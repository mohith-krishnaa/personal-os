export function validateProjectName(name: string): string | null {
  const trimmed = name.trim()
  if (!trimmed) return 'Project name is required'
  if (trimmed.length > 120) return 'Project name must be 120 characters or fewer'
  return null
}
