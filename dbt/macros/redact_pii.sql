{#- Replace e-mail addresses and phone-like numbers in free text (step 10).
    The regexes were measured on 2026-11-06: 7 reviews with an e-mail, 86 with a phone-like number.
    Phone matching can hit long product numbers too: we accept masking a few of them. -#}
{% macro redact_pii(column) -%}
REGEXP_REPLACE(
    REGEXP_REPLACE(
        {{ column }},
        r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}', '[email]'),
    r'\+?\d[\d .-]{8,}\d', '[phone]')
{%- endmacro %}
