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

### Utility functions
``` lua
-- An utility function, handy for adding the following set of per minute metrics with a single line of code to your functions
-- metric names are: func_name_avg, func_name_min, func_name_max, func_name_rpm
graphite.wrap_func_with_stat(name, func)
```

## Usage examples
``` lua
graphite.add_sec_metric('delete_rps_max', function() return box.stat().DELETE.rps end, graphite.max)

graphite.add('requests', 1)

graphite.max_per_min('max_mysql_query_time', query_time)

local function dostuff() end
dostuff = graphite.wrap_func_with_stat('dostuff', dostuff)
```
