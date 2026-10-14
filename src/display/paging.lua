-- Overlay paging over finished attempts. By default the overlay follows the newest page; paging
-- back holds a page until the next attempt finishes, then snaps back to newest.

local paging = {}

local state = {
    -- Selected page, or nil to follow the newest page.
    page = nil,
    pages = 1,
    finishedCount = 0,
    -- Set when the selected page changed and the overlay has not projected it yet.
    pending = false,
}

--- Rows `first`..`last` of `finishedCount` finished attempts to show, with the page shown and the
--- page count. `first > last` when there is nothing to show.
function paging.view(finishedCount, pageSize)
    if finishedCount ~= state.finishedCount then
        state.finishedCount = finishedCount
        state.page = nil
    end
    local pages = math.max(1, math.ceil(finishedCount / pageSize))
    state.pages = pages
    local page = state.page
    if page == nil or page > pages then
        state.page = nil
        page = pages
    end
    local first = (page - 1) * pageSize + 1
    local last = math.min(finishedCount, page * pageSize)
    return first, last, page, pages
end

function paging.previous()
    local page = state.page or state.pages
    if page > 1 then
        state.page = page - 1
        state.pending = true
    end
end

--- Moves one page forward; past the last page returns to following the newest page.
function paging.next()
    if state.page == nil then
        return
    end
    local page = state.page + 1
    state.page = page < state.pages and page or nil
    state.pending = true
end

--- Whether a page change is waiting to be projected; clears the flag.
function paging.takePending()
    local pending = state.pending
    state.pending = false
    return pending
end

function paging.isPending()
    return state.pending
end

return paging
