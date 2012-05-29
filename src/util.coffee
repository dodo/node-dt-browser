
# multiple changes of `this` context possible
class Callback
    constructor: () ->
        @callback = null
        @that = null
    use: (@callback) -> this
    replace: (@that) -> this
    call: =>
        @callback?.apply(@that, arguments) if @that?


class CancelableCallbacks
    constructor: (@canceled = no) ->
        @callbacks = []
    cancel: -> @canceled = yes
    reset:  -> @canceled = no
    # generates callback
    call: (callback) =>
        return =>
            if @canceled
                @callbacks.push callback
            else
                callback?(arguments...)


class DeferredCallbacks
    constructor: ->
        @reset()

    reset: () ->
        @callbacks = []
        @allowed   = null
        @done      = no

    complete: () ->
        @callbacks = null
        @allowed   = null
        @done      = yes

    # gnerates a callback
    callback: () ->
        return (->) if @done
        callback = =>
            if callback is @allowed
                while (cb = @callbacks?.shift())?
                    cb?(arguments...)
                @complete()
        @allowed = callback
        return callback

    call: (callback) =>
        return callback?() if @done
        @callbacks.push callback


removed = (el) ->
    el.closed is "removed"


# exports

module.exports = {
    Callback,
    CancelableCallbacks,
    DeferredCallbacks,
    removed,
}
