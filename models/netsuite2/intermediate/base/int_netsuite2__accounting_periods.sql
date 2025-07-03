{{ config(enabled=var('netsuite_data_model', 'netsuite') == var('netsuite_data_model_override','netsuite2')) }}

with accounting_periods as (
    select * 
    from {{ var('netsuite2_accounting_periods') }}
),

accounting_period_fiscal_calendars as (
    select * 
    from {{ var('netsuite2_accounting_period_fiscal_calendars') }}
),

{% if var('netsuite2__fiscal_calendar_enabled', false) %}
fiscal_calendar as (
    select *
    from {{ var('netsuite2_fiscal_calendar') }}
),

joined as (
    select 
        accounting_periods.*,
        accounting_period_fiscal_calendars.fiscal_calendar_id,
        fiscal_calendar.fiscal_month
    from accounting_periods
    left join accounting_period_fiscal_calendars
        on accounting_periods.accounting_period_id = accounting_period_fiscal_calendars.accounting_period_id
    left join fiscal_calendar
        on fiscal_calendar.fiscal_calendar_id = accounting_period_fiscal_calendars.fiscal_calendar_id
),

year_extract as (
    select 
        joined.*,
        {{ get_month_number("fiscal_month") }} as fiscal_start_month,
        extract(year from joined.starting_at) as calendar_year
    from joined
),

adjusted as (
    select 
        *,
        case 
            when extract(month from starting_at) < fiscal_start_month then calendar_year - 1
            else calendar_year
        end as fiscal_year_start
    from year_extract
),

final as (
    select
        *,
        {{ netsuite.date_from_parts('fiscal_year_start', 'fiscal_start_month', '1') }} as fiscal_year_trunc
    from adjusted
)
{% else %}

accounting_period_hierarchy as (

    select
        accounting_period_id,
        parent_id,
        1 as level,
        name as full_name
    from accounting_periods
    where
        parent_id is null

    union all

    select
        accounting_periods.accounting_period_id,
        accounting_periods.parent_id,
        accounting_period_hierarchy.level + 1,
        accounting_period_hierarchy.full_name || ' : ' || accounting_periods.name as full_name
    from accounting_periods
    join accounting_period_hierarchy
        on accounting_periods.parent_id = accounting_period_hierarchy.accounting_period_id
),

final as (

    select 
        accounting_periods.*,
        accounting_period_fiscal_calendars.fiscal_calendar_id,
        accounting_period_hierarchy.full_name,
        cast({{ dbt.date_trunc('year', 'accounting_periods.starting_at') }} as date) as fiscal_year_trunc

    from accounting_periods
    left join accounting_period_fiscal_calendars
        on accounting_periods.accounting_period_id = accounting_period_fiscal_calendars.accounting_period_id
    left join accounting_period_hierarchy
        on accounting_periods.accounting_period_id = accounting_period_hierarchy.accounting_period_id
)
{% endif %}

select *
from final
