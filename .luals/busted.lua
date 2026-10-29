---@meta

--- Editor-only definitions for the Busted globals used by the specs.
---@param name string
---@param callback fun()
function describe(name, callback) end

---@param name string
---@param callback fun()
function it(name, callback) end

---@param callback fun()
function setup(callback) end

---@param callback fun()
function teardown(callback) end

---@param callback fun()
function before_each(callback) end

---@param callback fun()
function after_each(callback) end

---@class BustedComparisonAssertions
---@field equal fun(expected: any, actual: any, message?: string)
---@field same fun(expected: any, actual: any, message?: string)

---@class BustedAssert
---@overload fun(value: any, message?: any, ...: any): any
---@field are BustedComparisonAssertions
---@field are_not BustedComparisonAssertions
---@field is_nil fun(value: any, message?: string)
---@field is_true fun(value: any, message?: string)
---@field is_false fun(value: any, message?: string)
---@field is_truthy fun(value: any, message?: string)

---@type BustedAssert
assert = {
    are = {
        equal = function(expected, actual, message) end,
        same = function(expected, actual, message) end,
    },
    are_not = {
        equal = function(expected, actual, message) end,
        same = function(expected, actual, message) end,
    },
    is_nil = function(value, message) end,
    is_true = function(value, message) end,
    is_false = function(value, message) end,
    is_truthy = function(value, message) end,
}
