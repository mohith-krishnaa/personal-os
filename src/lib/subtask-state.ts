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

export function afterSubtaskListLoadFailed<T>(
  currentItems: T[],
): { items: T[]; listLoaded: false } {
  return {
    items: currentItems,
    listLoaded: false,
  }
}
