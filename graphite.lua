fiber = require('fiber')
socket = require('socket')
log = require('log')

local _M = { }
local metrics = { }
local initialized = false
local common_stat_fiber = nil
local stat_fiber = nil

local sock = nil
local host = ''
local port = 0
local prefix = ''

local METRIC_SEC_TIMER = 0
local METRIC_SUM_PER_MIN = 1
local METRIC_SUM_PER_SEC = 2
local METRIC_VALUE = 3
local METRIC_AVG_PER_MIN = 4
local METRIC_MIN_PER_MIN = 5
local METRIC_MAX_PER_MIN = 6

local function send_graph(name, res, ts)
	if initialized == true then
		local graph = prefix .. name .. ' ' .. tostring(res) .. ' ' .. tostring(ts) .. '\n'
		sock:sendto(host, port, graph)
	end
end

local function send_metrics(ts, dt)
	for id, metric in pairs(metrics) do
		local mtype = metric[1]
		local name = metric[2]
		if mtype == METRIC_SEC_TIMER then
			local cnt = metric[3]
			local prev_cnt = metric[4]
			local values = metric[5]
			local aggr_fn = metric[7]

			if cnt > prev_cnt + 60 then
				prev_cnt = cnt - 60
			end

			if cnt ~= prev_cnt then
				local res = aggr_fn(prev_cnt, cnt - 1, values, dt)
				metric[4] = cnt
				send_graph(name, res, ts)
			end
		elseif mtype == METRIC_SUM_PER_MIN then
			local res = metric[3]
			send_graph(name, res, ts)
			metric[3] = 0
		elseif mtype == METRIC_SUM_PER_SEC then
			local res = metric[3] / dt
			send_graph(name, res, ts)
			metric[3] = 0
		elseif mtype == METRIC_VALUE then
			local res = metric[3]
			send_graph(name, res, ts)
		elseif mtype == METRIC_AVG_PER_MIN then
			local res = metric[3]
			if res ~= nil then
				metric[3] = nil
				if metric[5] > 1 then
					res = res + metric[4] / metric[5]
				end
				send_graph(name, res, ts)
			end
		elseif mtype == METRIC_MIN_PER_MIN then
			local res = metric[3]
			if res ~= nil then
				metric[3] = nil
				send_graph(name, res, ts)
			end
		elseif mtype == METRIC_MAX_PER_MIN then
			local res = metric[3]
			if res ~= nil then
				metric[3] = nil
				send_graph(name, res, ts)
			end
		end
	end
end

local function send_net_stats(ostats_net, stats_net, ts, dt)
	local res = 0

	res = (stats_net.SENT.total - ostats_net.SENT.total) / dt
	send_graph('net.sent_rps_avg', res, ts)
	send_graph('net.sent_total', stats_net.SENT.total, ts)

	res = (stats_net.EVENTS.total - ostats_net.EVENTS.total) / dt
	send_graph('net.events_rps_avg', res, ts)
	send_graph('net.events_total', stats_net.EVENTS.total, ts)

	res = (stats_net.LOCKS.total - ostats_net.LOCKS.total) / dt
	send_graph('net.locks_rps_avg', res, ts)
	send_graph('net.locks_total', stats_net.LOCKS.total, ts)

	res = (stats_net.RECEIVED.total - ostats_net.RECEIVED.total) / dt
	send_graph('net.received_rps_avg', res, ts)
	send_graph('net.received_total', stats_net.RECEIVED.total, ts)
end

local function send_box_stats(ostats_box, stats_box, ts, dt)
	local res = 0

	res = (stats_box.SELECT.total - ostats_box.SELECT.total) / dt
	send_graph('select_rps_avg', res, ts)

	res = (stats_box.REPLACE.total - ostats_box.REPLACE.total) / dt
	send_graph('replace_rps_avg', res, ts)

	res = (stats_box.UPDATE.total - ostats_box.UPDATE.total) / dt
	send_graph('update_rps_avg', res, ts)

	res = (stats_box.DELETE.total - ostats_box.DELETE.total) / dt
	send_graph('delete_rps_avg', res, ts)

	res = (stats_box.INSERT.total - ostats_box.INSERT.total) / dt
	send_graph('insert_rps_avg', res, ts)

	res = (stats_box.UPSERT.total - ostats_box.UPSERT.total) / dt
	send_graph('upsert_rps_avg', res, ts)

	res = (stats_box.CALL.total - ostats_box.CALL.total) / dt
	send_graph('call_rps_avg', res, ts)

	res = (stats_box.AUTH.total - ostats_box.AUTH.total) / dt
	send_graph('auth_rps_avg', res, ts)

	res = (stats_box.ERROR.total - ostats_box.ERROR.total) / dt
	send_graph('error_rps_avg', res, ts)
end

local function send_slab_stats(ts, dt)
	local slab_info = box.slab.info()
	for name, stat_ in pairs(slab_info) do
		local stat = string.gsub(stat_, '%%', '')
		send_graph(name, stat, ts)
	end

	send_graph('slab_alloc_arena', box.cfg.slab_alloc_arena, ts)
	send_graph('slab_alloc_factor', box.cfg.slab_alloc_factor, ts)
	send_graph('slab_alloc_minimal', box.cfg.slab_alloc_minimal, ts)
	send_graph('slab_alloc_maximal', box.cfg.slab_alloc_maximal, ts)

	local item_count = 0

	local slab_stats = box.slab.stats()
	for i, slab in pairs(slab_stats) do
		local item_size = slab['item_size']
		local slab_prefix = 'slab_' .. tostring(item_size) .. '.'
		for name, stat in pairs(slab) do
			if name ~= 'item_size' then
				if name == 'item_count' then
					item_count = item_count + tonumber(stat)
				end
				send_graph(slab_prefix .. name, stat, ts)
			end
		end
	end

	send_graph('item_count', item_count, ts)
end

local function init_stats()
	_M.add_sec_metric('select_rps_max', function() return box.stat().SELECT.rps end, _M.max)
	_M.add_sec_metric('replace_rps_max', function() return box.stat().REPLACE.rps end, _M.max)
	_M.add_sec_metric('update_rps_max', function() return box.stat().UPDATE.rps end, _M.max)
	_M.add_sec_metric('insert_rps_max', function() return box.stat().INSERT.rps end, _M.max)
	_M.add_sec_metric('upsert_rps_max', function() return box.stat().UPSERT.rps end, _M.max)
	_M.add_sec_metric('call_rps_max', function() return box.stat().CALL.rps end, _M.max)
	_M.add_sec_metric('delete_rps_max', function() return box.stat().DELETE.rps end, _M.max)
	_M.add_sec_metric('auth_rps_max', function() return box.stat().AUTH.rps end, _M.max)
	_M.add_sec_metric('error_rps_max', function() return box.stat().ERROR.rps end, _M.max)
end

local function send_stats(ostats_box, stats_box, ostats_net, stats_net, ts, dt)
	local res = 0

	ts = math.floor(ts)
	dt = math.floor(dt)

	if dt ~= 0 then
		-- send global stats
		send_graph("uptime", box.info.uptime or 0, ts)
		send_graph("lsn", box.info.server.lsn or 0, ts)

		if box.info.replication.status == "follow" then
			send_graph("replication_idle", box.info.replication.idle, ts)
			send_graph("replication_lag", box.info.replication.lag, ts)
		end

		-- send net stats
		send_net_stats(ostats_net, stats_net, ts, dt)

		-- send box stats
		send_box_stats(ostats_box, stats_box, ts, dt)

		-- send slab stats
		send_slab_stats(ts, dt)

		-- send custom metrics
		send_metrics(ts, dt)
	end
end

local function collect_stats()
	for id, metric in pairs(metrics) do
		local mtype = metric[1]
		if mtype == METRIC_SEC_TIMER then
			local cnt = metric[3]
			local values = metric[5]
			local metric_fn = metric[6]

			values[cnt % 60 + 1] = metric_fn()
			metric[3] = cnt + 1
		end
	end
end

_M.stop = function()
	if common_stat_fiber ~= nil then
		fiber.kill(common_stat_fiber:id())
		common_stat_fiber = nil
	end

	if stat_fiber ~= nil then
		fiber.kill(stat_fiber:id())
		stat_fiber = nil
	end

	if sock ~= nil then
		sock:close()
		sock = nil
	end

	metrics = {}
	initialized = false
end

_M.metrics = function()
	return metrics
end

_M.init = function(prefix_, host_, port_)
	prefix = prefix_ or 'localhost.tarantool.'
	host = host_ or 'nerv1.i'
	port = port_ or 2003

	_M.stop()

	init_stats()
	initialized = true

	common_stat_fiber = fiber.create(function()
		fiber.name("graphite_common_stat")

		sock = socket('AF_INET', 'SOCK_DGRAM', 'udp')

		if sock ~= nil then
			local t = fiber.time()
			while true do
				local ostats_box = box.stat()
				local ostats_net = box.stat.net()
				local nt = fiber.time()

				local st = 60 - (nt - t)
				fiber.sleep(st)

				local stats_box = box.stat()
				local stats_net = box.stat.net()

				t = fiber.time()
				send_stats(ostats_box, stats_box, ostats_net, stats_net, t, t - nt)
			end
		end
	end)

	if common_stat_fiber ~= nil then
		stat_fiber = fiber.create(function()
			fiber.name("graphite_stat")

			while true do
				collect_stats()
				fiber.sleep(1)
			end
		end
		)
	end

	log.info("Successfully initialized graphite module")
end

_M.sum = function(first, last, values, dt)
	local res = 0
	local i = first
	while i <= last do
		res = res + values[i % 60 + 1]
		i = i + 1
	end
	return res
end

_M.sum_per_sec = function(first, last, values, dt)
	local res = 0
	if dt ~= 0 then
		local i = first
		while i <= last do
			res = res + values[i % 60 + 1]
			i = i + 1
		end
		res = res / dt
	end
	return res
end

_M.max = function(first, last, values, dt)
	local res = nil
	local i = first
	while i <= last do
		local v = values[i % 60 + 1]
		if res == nil or v > res then
			res = v
		end
		i = i + 1
	end
	return res
end

_M.min = function(first, last, values, dt)
	local res = nil
	local i = first
	while i <= last do
		local v = values[i % 60 + 1]
		if res == nil or v < res then
			res = v
		end
		i = i + 1
	end
	return res
end

_M.last = function(first, last, values, dt)
	return values[last % 60 + 1]
end

_M.add_sec_metric = function(name, metric_fn, aggr_fn)
	local mtype = METRIC_SEC_TIMER
	local id = name .. '_' .. tostring(mtype)
	metrics[id] = { mtype, name, 0, 0, {}, metric_fn, aggr_fn }
end

_M.sum_per_min = function(name, value)
	local mtype = METRIC_SUM_PER_MIN
	local id = name .. '_' .. tostring(mtype)
	if metrics[id] == nil then
		metrics[id] = { mtype, name, value }
	else
		metrics[id][3] = metrics[id][3] + value
	end
end

_M.sum_per_sec = function(name, value)
	local mtype = METRIC_SUM_PER_SEC
	local id = name .. '_' .. tostring(mtype)
	if metrics[id] == nil then
		metrics[id] = { mtype, name, value }
	else
		metrics[id][3] = metrics[id][3] + value
	end
end

_M.add = function(name, value)
	local mtype = METRIC_VALUE
	local id = name .. '_' .. tostring(mtype)
	if metrics[id] == nil then
		metrics[id] = { mtype, name, value }
	else
		metrics[id][3] = metrics[id][3] + value
	end
end

_M.set = function(name, value)
	local mtype = METRIC_VALUE
	local id = name .. '_' .. tostring(mtype)
	metrics[id] = { mtype, name, value }
end

_M.avg_per_min = function(name, value)
	local mtype = METRIC_AVG_PER_MIN
	local id = name .. '_' .. tostring(mtype)
	if metrics[id] == nil or metrics[id][3] == nil then
		metrics[id] = { mtype, name, value, 0, 1 }
	else
		metrics[id][4] = metrics[id][4] + (value - metrics[id][3])
		metrics[id][5] = metrics[id][5] + 1
	end
end

_M.min_per_min = function(name, value)
	local mtype = METRIC_MIN_PER_MIN
	local id = name .. '_' .. tostring(mtype)
	if metrics[id] == nil or metrics[id][3] == nil then
		metrics[id] = { mtype, name, value }
	else
		if value < metrics[id][3] then
			metrics[id][3] = value
		end
	end
end

_M.max_per_min = function(name, value)
	local mtype = METRIC_MAX_PER_MIN
	local id = name .. '_' .. tostring(mtype)
	if metrics[id] == nil or metrics[id][3] == nil then
		metrics[id] = { mtype, name, value }
	else
		if value > metrics[id][3] then
			metrics[id][3] = value
		end
	end
end

_M.send = function(name, res, ts)
	send_graph(name, res, math.floor(ts))
end

_M.inc = function(name)
	_M.add(name, 1)
end

_M.status = function()
	local status = {}

	status['initialized'] = initialized

	if initialized == true then
		status['fibers'] = {}

		if common_stat_fiber ~= nil then
			table.insert(status['fibers'], {
				name = common_stat_fiber:name(),
				status = common_stat_fiber:status()
			})
		end

		if stat_fiber ~= nil then
			table.insert(status['fibers'], {
				name = stat_fiber:name(),
				status = stat_fiber:status()
			})
		end

		status['host'] = host
		status['port'] = port
		status['prefix'] = prefix
	end

	return status
end

return _M
