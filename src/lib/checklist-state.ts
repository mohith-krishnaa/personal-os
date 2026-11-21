export function afterChecklistItemCreated<T extends { position: number; created_at: string }>(
  currentItems: T[],
  createdItem: T,
  listLoaded: boolean,
): { items: T[]; shouldReload: boolean } {
  const items = [...currentItems, createdItem].sort((a, b) => {
    const positionDifference = a.position - b.position
    return positionDifference || a.created_at.localeCompare(b.created_at)
  })

  return {
    items,
    shouldReload: !listLoaded,
  }
}
