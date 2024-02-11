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

function print_intput_headers(r)
    local input = r:headers_in_table()
    local count = 0
    for k, v in pairs(input) do
        r.headers_out['Y-' .. k ] = v
        count = count + 1
    end
    r.headers_out["Y-IN"] = count

    return nil;
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



function get_url_segment_number(r, r_unparsed_uri)
    -- lua regex reference
    r:debug(("r.unparsed_uri: %s"):format(r_unparsed_uri))
    -- local segment_number = string.match(r.unparsed_uri, "^.*dash/.*[video|audio|text|subtitle]=%d+-(%d+)")
    -- It seems that lua does not allow (\w+|_): a word or no value
    local segment_number = nil
    segment_number = string.match(r_unparsed_uri, "^.*dash/.*[video|audio|text|subtitle|sub]_%w+=%d+-(%d+).json$")
    if segment_number == nil then
        segment_number = string.match(r_unparsed_uri, "^.*dash/.*[video|audio|text|subtitle|sub]=%d+-(%d+).json$")
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

function create_wmpaceinfo(r, segment_number, pos)
    r.headers_out['position'] = "" .. pos .. "" -- tostring() does not work
    local seg_num_int = tonumber(segment_number)

	local keys = {"position", "segment_number", "segment_regex"}
	local data =
	  {
		position = pos,
		segment_number = seg_num_int,
		segment_regex = "\"foo\"",
	  }
	local result = create_json_object(keys, data)

    r.headers_out['WMPaceInfo'] = result
    local json_str = result
    r.headers_out['Content-Type'] = 'application/json'
    return json_str;
end

function create_wmpaceinfo_sidecar_file(r, is_init_segment)
    -- local segments = '"segment_regex": "foo", "segment_number": tonumber(segment_number)'
    -- r.headers_out['is_init_segment'] = "" .. tostring(is_init_segment) .. ""
    local segment_number = nil
    local pos = nil
    if is_init_segment == true then
        pos = -1
        segment_number = 0
    else
        -- Separate request (r) and unparsed uri to reuse function
        -- get_url_segment_number()
        segment_number = get_url_segment_number(r, r.unparsed_uri)
        r:debug(("segment_number: %s"):format(segment_number))
        pos = tonumber(segment_number) - 1
    end
    return create_wmpaceinfo(r, segment_number, pos)
end

function add_cache_headers(r)
    r.headers_out['Cache-Control'] = "max-age=3600"
    return nil
end

function create_r_unparsed_uri(r)
    local representation_id = r.headers_in['Representation-ID']
    local url_first_part = string.match(r.unparsed_uri, '^(.*/WMPaceInfo/.*=)-%w+.json$')
    local url_second_part = string.match(r.unparsed_uri, '^.*/WMPaceInfo/.*=(-%w+.json)$')
    local url_created = url_first_part .. representation_id .. url_second_part
    -- r.headers_out["url_first_part"] = url_first_part
    -- r.headers_out["url_second_part"] = url_second_part
    -- r.headers_out["url_created"] = url_created
    return url_created;
end

function create_wmpaceinfo_sidecar_file_req_header(r, is_init_segment)
    -- local segments = '"segment_regex": "foo", "segment_number": tonumber(segment_number)'
    -- r.headers_out['is_init_segment'] = "" .. tostring(is_init_segment) .. ""
    local segment_number = nil
    local pos = nil
    if is_init_segment == true then
        pos = -1
        segment_number = 0
    else
        local created_uri = create_r_unparsed_uri(r)
        segment_number = get_url_segment_number(r, created_uri)
        r:debug(("segment_number: %s"):format(segment_number))
        pos = tonumber(segment_number) - 1
    end
    return create_wmpaceinfo(r, segment_number, pos)
end

-- Extract Unfieid Streaming's segment number (--time) that is encoded in
-- the URL
function filter(r)
    r:debug(("type(r.unparsed_uri): %s"):format(type(r.unparsed_uri)))
     -- Only process requests that have .json extension (e.g., sidecar files)
     -- Match only media segments with json extension
    local uri_match = string.match(r.unparsed_uri, '^.*WMPaceInfo/.*[video|audio_%w+|text|subtitle|sub]=.*.json$')

    if uri_match ~= nil then
        -- "^.*dash\/.*(video|audio_\w+|text|subtitle|sub)=(-\w+|\w+).json$"
        r:debug(("uri_match: %s"):format((uri_match)))
        r:debug(("type(uri_match): %s"):format(type(uri_match)))
        --r.headers_out['X-ri_match'] = uri_match
        -- print_intput_headers(r)
        -- Check if it has the correct JSON URL format
        --
        -- /ingress-a/WMPaceInfo/ingress.isml/dash/ingress-video=500000.json
        local uri_init_match = string.match(r.unparsed_uri, '^.*/WMPaceInfo/.*=[0-9]+.json$')
        local json_body_side_car_file_no_watermark = nil
        if uri_init_match ~= nil then
            json_body_side_car_file_no_watermark = create_wmpaceinfo_sidecar_file(r, true)
            add_cache_headers(r)
            r.status = 200
            r:puts(json_body_side_car_file_no_watermark)
            return apache2.OK
        else
            -- /ingress-a/WMPaceInfo/ingress.isml/dash/ingress-video=-889088832.json
            -- Request Header for Representation -> "Representation-ID: 500000"
            local uri_media_match = string.match(r.unparsed_uri, '^.*/WMPaceInfo/.*=-[0-9]+.json$')
            if uri_media_match ~= nil and r.headers_in['Representation-ID'] then

                -- r.unparsed_uri = url_first_part .. representation_id .. url_second_part
                json_body_side_car_file_no_watermark = create_wmpaceinfo_sidecar_file_req_header(r, false)
                add_cache_headers(r)
                r.status = 200
                r:puts(json_body_side_car_file_no_watermark)
                return apache2.OK
            else
                r.headers_out['log'] = "URL does not contain required request Header"
                r:puts("URL does not contain required request Header")
                r.status = 404
                return apache2.DECLINED
            end
        end
    else
        r.headers_out['log'] = "URL not matching as a side car file with WMPaceInfo virtual path."
        r:puts("URL not matching as a side car file with WMPaceInfo virtual path.")
        r.status = 404
        return apache2.DECLINED
    end

    return apache2.OK
end
