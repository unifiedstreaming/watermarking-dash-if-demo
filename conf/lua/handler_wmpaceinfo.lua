require "string"


function print_headers_table(r)
    local headers_out = r:headers_out_table()
    for k, v in pairs(headers_out) do
        r:info(("Header key, value is: %s: %s"):format(k, v))
    end
    return nil;
end
function print_apache_urls_as_header(r)
    r.headers_out['r.the_request'] = r.the_request
    r.headers_out['r.unparsed_uri'] = r.unparsed_uri
    r.headers_out['r.uri'] = r.uri
    return nil;
end

function get_url_segment_number(r)
    -- lua regex reference
    r:debug(("r.unparsed_uri: %s"):format(r.unparsed_uri))
    -- local segment_number = string.match(r.unparsed_uri, "^.*dash/.*[video|audio|text|subtitle]=%d+-(%d+)")
    -- It seems that lua does not allow (\w+|_): a word or no value
    local segment_number = nil
    segment_number = string.match(r.unparsed_uri, "^.*dash/.*[video|audio|text|subtitle|sub]_%w+=%d+-(%d+).m4s$")
    if segment_number == nil then
        segment_number = string.match(r.unparsed_uri, "^.*dash/.*[video|audio|text|subtitle|sub]=%d+-(%d+).m4s$")
    end

    if segment_number == nil then
        r.headers_out['log'] = "URL not matching with regex. Verify the URL and regex pattern!"
    end

    r:debug(("segment_number: %s"):format((segment_number)))
    r:debug(("type(segment_number): %s"):format((type(segment_number))))

    -- r.headers_out['segment_number'] = segment_number
    return segment_number
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
    local pos = nil
    if is_init_segment == true then
        pos = -1
        segment_number = 0
    else
        r:debug(("segment_number: %s"):format(segment_number))
		-- For vod the first media segment (SegmentTempalte $Numer$)
		-- is one-based index
        -- pos = tonumber(segment_number) - 1
		-- Pattern fixed  size of 10. For instance, 1010101010
		pos = math.floor(math.fmod(segment_number, 10))
    end
    -- r.headers_out['position'] = "" .. pos .. "" -- tostring() does not work
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
	return nil
end

function create_wmpaceinfo(r)
	-- hachky way to identify initialization segments
	if string.find(r.unparsed_uri,'.dash$') then
		create_wmpaceinfo_sidecar_file(r, true)
	elseif string.find(r.unparsed_uri,'.m4s$') then
		local uri_match = string.match(r.unparsed_uri, '^.*=[0-9]+-[0-9]+.m4s$')

	    if uri_match ~= nil then
			-- r.headers_out['log'] = "Entered /translate-name"
			create_wmpaceinfo_sidecar_file(r, false)
		end
	end

	return nil
end

function filter(r)
 	-- print_apache_urls_as_header(r)
    -- print_headers_table(r)
	create_wmpaceinfo(r)

    r:debug("Starting first coroutine")
    -- coroutine.yield("(Handled by myOutputFilter)<br/>\n")
    -- After we have yielded, buckets will be sent to us, one by one, and we can
    -- do whatever we want with them and then pass on the result.
    -- Buckets are stored in the global variable 'bucket', so we create a loop
    -- that checks if 'bucket' is not nil:
    while bucket ~= nil do
        -- local output = mangle(bucket) -- Do some stuff to the content
        -- r:debug(("type(): %s"):format(type(bucket)))
        -- r:debug(("string.len(bucket): %s"):format(string.len(bucket)))
        -- r:debug("Some bucket")
        -- coroutine.yield(output) -- Return our new content to the filter chain
        coroutine.yield(bucket) -- Return our new content to the filter chain
        -- coroutine.yield(json_str)
    end
    r:debug("Output headers after returning the buckets")

end
