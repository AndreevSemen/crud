local checks = require('checks')
local errors = require('errors')
local vshard = require('vshard')

local call = require('crud.common.call')
local utils = require('crud.common.utils')
local sharding = require('crud.common.sharding')
local dev_checks = require('crud.common.dev_checks')

local ReplaceError = errors.new_class('Replace', { capture_stack = false })

local replace = {}

local REPLACE_FUNC_NAME = '_crud.replace_on_storage'

local function replace_on_storage(space_name, tuple)
    dev_checks('string', 'table')

    local space = box.space[space_name]
    if space == nil then
        return nil, ReplaceError:new("Space %q doesn't exist", space_name)
    end

    return space:replace(tuple)
end

function replace.init()
   _G._crud.replace_on_storage = replace_on_storage
end

--- Insert or replace a tuple in the specified space
--
-- @function tuple
--
-- @param string space_name
--  A space name
--
-- @param table tuple
--  Tuple
--
-- @tparam ?number opts.timeout
--  Function call timeout
--
-- @tparam ?number opts.bucket_id
--  Bucket ID
--  (by default, it's vshard.router.bucket_id_strcrc32 of primary key)
--
-- @return[1] object
-- @treturn[2] nil
-- @treturn[2] table Error description
--
function replace.tuple(space_name, tuple, opts)
    checks('string', 'table', {
        timeout = '?number',
        bucket_id = '?number|cdata',
    })

    opts = opts or {}

    local space = utils.get_space(space_name, vshard.router.routeall())
    if space == nil then
        return nil, ReplaceError:new("Space %q doesn't exist", space_name)
    end

    local bucket_id, err = sharding.tuple_set_and_return_bucket_id(tuple, space, opts.bucket_id)
    if err ~= nil then
        return nil, ReplaceError:new("Failed to get bucket ID: %s", err)
    end

    local result, err = call.rw_single(
        bucket_id, REPLACE_FUNC_NAME,
        {space_name, tuple}, {timeout=opts.timeout})


    if err ~= nil then
        return nil, ReplaceError:new("Failed to replace: %s", err)
    end

     return {
        metadata = table.copy(space:format()),
        rows = {result},
    }
end

--- Insert or replace an object in the specified space
--
-- @function object
--
-- @param string space_name
--  A space name
--
-- @param table obj
--  Object
--
-- @tparam ?table opts
--  Options of replace.tuple
--
-- @return[1] object
-- @treturn[2] nil
-- @treturn[2] table Error description
--
function replace.object(space_name, obj, opts)
    checks('string', 'table', '?table')

    opts = opts or {}

    local space = utils.get_space(space_name, vshard.router.routeall())
    if space == nil then
        return nil, ReplaceError:new("Space %q doesn't exist", space_name)
    end

    local space_format = space:format()
    local tuple, err = utils.flatten(obj, space_format)
    if err ~= nil then
        return nil, ReplaceError:new("Object is specified in bad format: %s", err)
    end

    return replace.tuple(space_name, tuple, opts)
end

return replace
