Vue.filter('numberformat', function (value, locale = 'en-US', options = {}) {
  if ( ! value) return '';

  return Intl.NumberFormat(locale, options).format(value);
});