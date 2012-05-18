{ Animation } = require 'animation'
{ singlton_callback, deferred_callbacks,
  cancelable_and_retrivable_callbacks,
  removed } = require './util'
{ isArray } = Array

EVENTS = [
    'add', 'end'
    'show', 'hide'
    'attr','text', 'raw'
    'remove', 'replace'
]

defaultfn = {}
EVENTS.forEach (e) ->
    defaultfn[e] = -> throw new Error "no specific fn for #{e} defined" # dummy


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
        @builder._browser_done = deferred_callbacks()
        do @builder._browser_done.callback() # builder is allways done
        # register ready handler
        @template.register 'ready', (tag, next) ->
            # when tag is already in the dom its fine,
            #  else wait until it is inserted into dom
            if tag._browser_ready is yes
                next(tag)
            else
                tag._browser_ready = ->
                    next(tag)
        return this

    use: (plugin) ->
        plugin?.call(this, this)
        return this

    listen: () ->
        for event in EVENTS
            if (listener = this["on#{event}"])?
                @template.on(event, listener.bind(this))
        return this

    make: -> # create a dom object
        throw new Error "Adapter::make not defined."

    # flow control : eventlisteners

    onadd: (parent, el) ->
        return if removed el
        @make(el) # create a dom object
        that = this
        el._browser_manip    ?= cancelable_and_retrivable_callbacks()
        el._browser_done     ?= deferred_callbacks()
        parent._browser_done ?= deferred_callbacks()
        el._browser_manip.reset()
        while (cb = el._browser_manip.callbacks.shift())?
            @animation.push(cb)

        ecb = el._browser_done.callback()
        pcb = parent._browser_done.callback()
        if el is el.builder then ecb() else el.ready(ecb)
        if parent is parent.builder then pcb() else parent.ready(pcb)

        el._browser_insert ?= singlton_callback el, ->
            return if removed this
            that.insert_callback(this)
        el._browser_insert.replace?(el)

        el._browser_parent_done ?= singlton_callback el, ->
            return if removed this
            that.parent_done_callback(this)
        el._browser_parent_done.replace(el)
        parent._browser_done(el._browser_parent_done)

    onreplace: (oldtag, newtag) ->
        return if removed(oldtag) or removed(newtag)
        newtag._browser_parent_done ?= oldtag._browser_parent_done
        newtag._browser_insert      ?= oldtag._browser_insert
        newtag._browser_done        ?= oldtag._browser_done
        oldtag._browser_parent_done  = null
        oldtag._browser_insert       = null
        oldtag._browser_done         = null

        @onadd(oldtag.parent, newtag)

        oldtag._browser_manip?.cancel?()
        newtag._browser_manip.reset()
        # if manip left from last time run them
        while (cb = newtag._browser_manip.callbacks.shift())?
            @animation.push(cb)

        if newtag._browser_insert is true
            that = this
            newtag._browser_replace ?= oldtag._browser_replace
            oldreplacerequest = newtag._browser_replace?
            newtag._browser_replace ?= singlton_callback newtag, ->
                return if removed this
                that.replace_callback(oldtag, this)
            newtag._browser_replace.replace?(newtag)
            oldtag._browser_replace = null
            unless oldreplacerequest
                @animation.push(newtag._browser_replace)

    ontext: (el, text) ->
        el._browser_manip ?= cancelable_and_retrivable_callbacks(yes)
        @animation.push el._browser_manip =>
            @fn.text(el, text)

    onraw: (el, html) ->
        el._browser_manip ?= cancelable_and_retrivable_callbacks(yes)
        @animation.push el._browser_manip =>
            @fn.raw(el, html)

    onattr: (el, key, value) ->
        el._browser_manip ?= cancelable_and_retrivable_callbacks(yes)
        @animation.push el._browser_manip =>
            @fn.attr(el, key, value)

    onshow: (el) ->
        @fn.show(el)

    onhide: (el) ->
        @fn.hide(el)

    onremove: (el, opts) ->
        @fn.remove(el, opts)
        el._browser_parent_done?.replace(null)
        el._browser_done?.reset()
        el._browser_manip?.cancel()
        delete el._browser_parent_done
        delete el._browser_replace
        delete el._browser_insert
        unless opts.soft
            delete el._browser_manip
            delete el._browser_done

    # ready callbacks

    insert_callback: (el) ->
        @fn.add(el.parent, el)
        el._browser_ready?()
        el._browser_ready = yes
        el._browser_insert = yes

    parent_done_callback: (el) ->
        if el.parent is el.parent.builder
            bool = (not el.parent.parent? or
                       (el.parent.parent is el.parent.parent?.builder and # FIXME recursive?
                        el.parent.parent?._browser_insert is true))
            if bool and el.parent._browser_insert is true
                @animation.push(el._browser_insert)
            else
                el._browser_insert?()
        else
            @animation.push(el._browser_insert)

    replace_callback: (oldtag, newtag) ->
        @fn.replace(oldtag, newtag)

# exports


module.exports = {
    Adapter:BrowserAdapter,
    fn:defaultfn,
}

