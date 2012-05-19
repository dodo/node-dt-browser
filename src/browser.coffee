{ Animation } = require 'animation'
{ Callback, CancelableCallbacks, DeferredCallbacks,
  removed } = require './util'
{ isArray } = Array

SHARED = ['parent_done', 'insert', 'replace', 'done']

EVENTS = [
    'add', 'end'
    'show', 'hide'
    'attr','text', 'raw'
    'remove', 'replace'
]

defaultfn = {}
EVENTS.forEach (e) ->
    defaultfn[e] = -> throw new Error "no specific fn for #{e} defined" # dummy

prepare_deferred_done = (el) ->
    (el._browser ?= new BrowserState).done ?= new DeferredCallbacks

prepare_cancelable_manip = (el, canceled) ->
    (el._browser ?= new BrowserState).manip ?= new CancelableCallbacks(canceled)

##
# this contains the tag specific browser state from the user/developer event loop,
#   which includes references to
#   - state objects from the requestAnimationFrame event loop
class BrowserState
    initialize: (prev) ->
        @parent_done ?= new Callback
        @insert      ?= new Callback
        @manip       ?= new CancelableCallbacks
        @done        ?= new DeferredCallbacks
        @manip.reset()
        this

    mergeInto: (state) ->
        for key in SHARED
            state[key] ?= this[key]
            this[key] = null
        state

    destroy: (opts) ->
        @manip?.cancel()
        @done?.reset()
        if opts.soft
            this[key] = null for key in SHARED
        else
            delete this[key] for key in SHARED
            delete manip
        this

##
# the main purpose of this is to sync two event loops:
#   the event loop from which the template gets updated
#                   with
#   the requestAnimationFrame event loop
class BrowserAdapter
    constructor: (@template, opts = {}) ->
        @builder = @template.xml ? @template
        # defaults
        opts.timeoutexecution ?= '32ms'
        opts.execution        ?= '8ms' # half of 16ms (60 FPS), the other half is for the browser
        opts.timeout          ?= '120ms'
        opts.toggle           ?= on
        # init requestAnimationFrame handler
        @animation = new Animation(opts)
        @animation.start()
        # init browser manipulation functions
        @fn ?= {}
        for n,f of defaultfn
            @fn[n] ?= f.bind(this)
        @initialize()
        # allow plugins as options
        opts.use ?= []
        opts.use = [opts.use] unless isArray opts.use
        @use(plugin) for plugin in opts.use

    initialize: () ->
        do @listen
        # prefill builder with state
        @make(@builder) # create a dom object
        do prepare_deferred_done(@builder).callback() # builder is allways done
        # register ready handler
        @template.register 'ready', (tag, next) ->
            tag._browser ?= new BrowserState
            # when tag is already in the dom its fine,
            #  else wait until it is inserted into dom
            if tag._browser.ready is yes
                next(tag)
            else
                tag._browser.ready = next
        return this

    use: (plugin) ->
        plugin?.call(this, this)
        return this

    listen: () ->
        for event in EVENTS when (listener = this["on#{event}"])?
            @template.on(event, listener.bind(this))
        return this

    make: -> # create a dom object
        throw new Error "Adapter::make not defined."

    createPlaceholder: -> # create a dom object
        throw new Error "Adapter::createPlaceholder not defined."

    removePlaceholder: -> # create a dom object
        throw new Error "Adapter::removePlaceholder not defined."

    # flow control : eventlisteners

    onadd: (parent, el) ->
        return if removed el
        @make(el) # create a dom object
        that = this
        (el._browser ?= new BrowserState).initialize()
        while (cb = el._browser.manip.callbacks.shift())?
            @animation.push(cb)

        ecb = el._browser.done.callback()
        pcb = parent._browser.done.callback()
        if el is el.builder then ecb() else el.ready(ecb)
        if parent is parent.builder then pcb() else parent.ready(pcb)

        el._browser.insert.replace?(el).callback ?= ->
            return if removed this
            that.insert_callback(this)

        el._browser.parent_done.replace?(el).callback ?= ->
            return if removed this
            that.parent_done_callback(this)
        prepare_deferred_done(parent).call(el._browser.parent_done.call)

    onreplace: (oldtag, newtag) ->
        return if removed(oldtag) or removed(newtag)
        newtag._browser ?= new BrowserState
        oldtag._browser?.mergeInto(newtag._browser)

        @onadd(oldtag.parent, newtag)

        oldtag._browser?.destroy(soft:yes)
        newtag._browser.manip.reset()
        # if manip left from last time run them
        while (cb = newtag._browser.manip.callbacks.shift())?
            @animation.push(cb)

        if newtag._browser.insert is true
            that = this
            oldreplacerequest = newtag._browser.replace?.callback?
            newtag._browser.replace ?= new Callback
            newtag._browser.replace.replace(newtag).callback ?= ->
                return if removed this
                that.replace_callback(oldtag, this)
            unless oldreplacerequest
                @animation.push(newtag._browser.replace.call)

    ontext: (el, text) ->
        @animation.push prepare_cancelable_manip(el, yes).call =>
            @fn.text(el, text)

    onraw: (el, html) ->
        @animation.push prepare_cancelable_manip(el, yes).call =>
            @fn.raw(el, html)

    onattr: (el, key, value) ->
        @animation.push prepare_cancelable_manip(el, yes).call =>
            @fn.attr(el, key, value)

    onshow: (el) ->
        @fn.show(el)

    onhide: (el) ->
        @fn.hide(el)

    onremove: (el, opts) ->
        @fn.remove(el, opts)
        el._browser?.destroy(opts)
        delete el._browser unless opts.soft

    # ready callbacks

    insert_callback: (el) ->
        if el is el.builder and el.isempty
            el._browser.wrapped = yes
            @createPlaceholder(el)
        @fn.add(el.parent, el)
        if el.parent._browser.wrapped
            el.parent._browser.wrapped = no
            @removePlaceholder(el.parent)
        el._browser.ready?(el)
        el._browser.ready  = yes
        el._browser.insert = yes

    parent_done_callback: (el) ->
        if el.parent is el.parent.builder
            bool = (not el.parent.parent? or
                       (el.parent.parent is el.parent.parent?.builder and # FIXME recursive?
                        el.parent.parent?._browser?.insert is true))
            if bool and el.parent._browser?.insert is true
                @animation.push(el._browser.insert.call)
            else
                el._browser.insert.call?()
        else
            @animation.push(el._browser.insert.call)
        el._browser.parent_done = yes

    replace_callback: (oldtag, newtag) ->
        if newtag is newtag.builder and newtag.isempty
            newtag._browser.wrapped = yes
            @createPlaceholder(newtag)
        @fn.replace(oldtag, newtag)
        newtag._browser.replace = null

# exports


module.exports = {
    Adapter:BrowserAdapter,
    fn:defaultfn,
}

