const filterMixin = {
    methods: {
        numberformat: function (value, locale = 'en-US', options = {}) {
            if ( ! value ) value = 0;

            return Intl.NumberFormat(locale, options).format(value);
        }
    }
}