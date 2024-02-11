require('apache2')

function add_output_headers(r)
    -- r.headers_out['r.the_request'] = r.the_request
    r.headers_out['r.unparsed_uri'] = r.unparsed_uri

    -- local r_media_unparsed_uri = r.unparsed_uri
    -- r_media_unparsed_uri = r_media_unparsed_uri:gsub(".json", ".m4s")
    -- r.headers_out['r_media_unparsed_uri'] = r_media_unparsed_uri
    -- r.headers_out['r.uri'] = r.uri
    return 0
end

function add_cache_headers(r)
    -- r.headers_out['Cache-Control'] = "max-age=3600"
    r.headers_out['Cache-Control'] = "no-cache, no-store, must-revalidate"
    return nil
end

function sort_upper(a, b)
    return a:upper() < b:upper();
end

function sort_str_int(a, b)
    return a < b;
end

function compare(a,b)
    return a[1] < b[1]
end

function spairs(t, order)
    -- collect the keys
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end

    -- if order function given, sort by it by passing the table and keys a, b,
    -- otherwise just sort the keys
    if order then
        table.sort(keys, function(a,b) return order(t, a, b) end)
    else
        table.sort(keys)
    end

    -- return the iterator function
    local i = 0
    return function()
        i = i + 1
        if keys[i] then
            return keys[i], t[keys[i]]
        end
    end
end

function create_json_object(keys, data)
	local result = {}
	for i=1, #keys do
	  local res = data[keys[i]]
	  table.insert(result, string.format("\"%s\":%s", keys[i], res))
	end
	result = "{" .. table.concat(result, ",") .. "}"
	result = "{" .. "\"version\": 1, \"segments\":" .. "[" .. result .. "]" .. "}"
	return result;
end


function create_wmpaceinfo_sidecar_file(r, is_init_segment)
    local segment_number = get_url_segment_number(r)
    -- local segments = '"segment_regex": "foo", "segment_number": tonumber(segment_number)'
    -- r.headers_out['is_init_segment'] = "" .. tostring(is_init_segment) .. ""
    local pos = nil
    if is_init_segment == true then
        pos = -1
        segment_number = 0
    else
        r:debug(("segment_number: %s"):format(segment_number))
        pos = tonumber(segment_number) - 1
    end
    r.headers_out['position'] = "" .. pos .. "" -- tostring() does not work
    local seg_num_int = tonumber(segment_number)
    -- local segs = {
    --     position=pos,
    --     segment_number=seg_num_int,
    --     segment_regex="foo",
    -- }
	local keys = {"position", "segment_number", "segment_regex"}
	local data =
	  {
		position = pos,
		segment_number = seg_num_int,
		segment_regex = "\"foo\"",
	  }
	local result = create_json_object(keys, data)

    r.headers_out['WMPaceInfo'] = result
    json_str = result
    r.headers_out['Content-Type'] = 'application/json'
    return json_str;
end

-- Extract Unfieid Streaming's segment number (--time) that is encoded in
-- the URL
function get_url_segment_number(r)
    -- lua regex reference
    r:debug(("r.unparsed_uri: %s"):format(r.unparsed_uri))
    -- local segment_number = string.match(r.unparsed_uri, "^.*dash/.*[video|audio|text|subtitle]=%d+-(%d+)")
    -- It seems that lua does not allow (\w+|_): a word or no value
    local segment_number = nil
    segment_number = string.match(r.unparsed_uri, "^.*dash/.*[video|audio|text|subtitle|sub]_%w+=%d+-(%d+).json$")
    if segment_number == nil then
        segment_number = string.match(r.unparsed_uri, "^.*dash/.*[video|audio|text|subtitle|sub]=%d+-(%d+).json$")
    end

    if segment_number == nil then
        r.headers_out['log'] = "URL not matching with regex. Verify the URL and regex pattern!"
        r.status = 404
        return apache2.DECLINED
    end

    r:debug(("segment_number: %s"):format((segment_number)))
    r:debug(("type(segment_number): %s"):format((type(segment_number))))

    r.headers_out['segment_number'] = segment_number
    return segment_number
end

function filter(r)

    r:debug(("type(r.unparsed_uri): %s"):format(type(r.unparsed_uri)))
     -- Only process requests that have .json extension (e.g., sidecar files)
     -- Match only media segments with json extension
    local uri_match = string.match(r.unparsed_uri, '^.*/WMPaceInfo/.*=[0-9]+-[0-9]+.json$')
    r:debug(("uri_match: %s"):format((uri_match)))
    r:debug(("type(uri_match): %s"):format(type(uri_match)))

    if uri_match ~= nil then
        add_output_headers(r)
        r.headers_out['log'] = "Entered /translate-name"
        local json_body_sidecar_file = create_wmpaceinfo_sidecar_file(r, false)
        add_cache_headers(r)
        r:puts(json_body_sidecar_file)
        -- r:debug(("fileSize: %s"):format(string.len(json_body_sidecar_file)))
        r.status = 200
        return apache2.OK
    else
        -- Verify it is not an object that doest need any watermarking
        -- (e.g., init media segment)
        local uri_init_match = string.match(r.unparsed_uri, '^.*/WMPaceInfo/.*=[0-9]+.json$')
        if uri_init_match ~= nil then
            local json_body_side_car_file_no_watermark = create_wmpaceinfo_sidecar_file(r, true)
            add_cache_headers(r)
            r:puts(json_body_side_car_file_no_watermark)
            r.status = 200
            return apache2.OK
        else
            r.headers_out['log'] = "URL not matching as a side car file with WMPaceInfo virtual path."
            r.status = 404
            return apache2.DECLINED
        end
    end
end
