export function afterSubtaskCreated<T>(
  currentItems: T[],
  createdItem: T,
  listLoaded: boolean,
): { items: T[]; shouldReload: boolean } {
  return {
    items: [...currentItems, createdItem],
    shouldReload: !listLoaded,
  }
}
