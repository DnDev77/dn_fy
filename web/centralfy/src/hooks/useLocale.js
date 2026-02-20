export const useLocale = (localeData) => {
  const t = (key, ...args) => {
    if (!localeData) return key;
    const parts = key.split('.');
    let value = localeData;
    for (const part of parts) {
      if (value && typeof value === 'object') {
        value = value[part];
      } else {
        return key;
      }
    }
    if (typeof value !== 'string') return key;
    if (args.length > 0) {
      let i = 0;
      return value.replace(/%[sd.0-9]*[sdf]/g, () => args[i++] ?? '');
    }
    return value;
  };
  return t;
};