# Tarantool 1.6 graphite module

## Usage examples

``` lua
local graphite = require('graphite')

-- initialize standard metrics, transmit them to graphite @ 192.168.1.2:3010
graphite.init('localhost.1_instance.', '192.168.1.2', 3010)
```

## API

### Metrics

```-- adds new metric, values are probed every second by calling metric_fn, aggregated by calling aggr_fn on the series
graphite.add_sec_metric(name, metric_fn, aggr_fn)```

`graphite.sum_per_min(name, value)`

`graphite.sum_per_sec(name, value)`

`graphite.avg_per_min(name, value)`

`graphite.min_per_min(name, value)`

`graphite.max_per_min(name, value)`

`graphite.add(name, value) -- adds to current graphite metric value`

`graphite.inc(name) -- alias for graphite.add(name, 1)`

### Aggregation functions

Builtin aggregation functions to be used with add_sec_metric

`graphite.sum`

`graphite.sum_per_sec`

`graphite.max`

`graphite.min`

`graphite.last`

### Transmission functions
``` lua
-- transmits metric value to graphite
graphite.send(name, res, timestamp)
```
### Expirationd metrics helper function
add_expirationd_callbacks wraps is_tuple_expired and process_expired_tuple functions
of every expirationd task and calls proper callback after it's being invoked
callback function receives (name, start, stop, args)
name - expirationd task name
start, stop - result of clock.time64() call before and after invocation of:
is_tuple_expired_callback, process_expired_tuple_callback
args - passed to callbacks as additional context
``` lua
graphite.add_expirationd_callbacks(is_tuple_expired_callback, 
		process_expired_tuple_callback, args)
```

## Usage examples
`graphite.add_sec_metric('delete_rps_max', function() return box.stat().DELETE.rps end, graphite.max)`

`graphite.add('requests', 1)`

`graphite.max_per_min('max_mysql_query_time', query_time)`

If you have a common set of metrics which you need to apply to every function in your module you can create a wrapper and apply needed set of metrics with a single line of code like in example below.

``` lua
local graphite = require('graphite')
local clock = require('clock')

local function pack(...)
	return {r = {...}, n = select('#', ...)}
end

local function module_common_stat(name, func)
	local stat_name = {
		avg = 'func_' .. name .. '_avg',
		min = 'func_' .. name .. '_min',
		max = 'func_' .. name .. '_max',
		rpm = 'func_' .. name .. '_rpm',
	}

	return function(...)
		local start = clock.time64()
		local ret = pack(func(...))
		local delta = tonumber(clock.time64() - start) / 1000

		graphite.avg_per_min(stat_name['avg'], delta)
		graphite.min_per_min(stat_name['min'], delta)
		graphite.max_per_min(stat_name['max'], delta)
		graphite.sum_per_min(stat_name['rpm'], 1)

		return unpack(ret.r, 1, ret.n)
	end
end

-- your module functions
local function dostuff() end
local function domorestuff() end

-- one line to apply avg, min, max, rpm set of metrics to dostuff and domorestuff functions
dostuff = module_common_stat('dostuff', dostuff)
domorestuff = module_common_stat('domorestuff', domorestuff)
```
