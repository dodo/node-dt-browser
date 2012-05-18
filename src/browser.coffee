{ Animation } = require 'animation'
{ singlton_callback, deferred_callbacks,
  cancelable_and_retrivable_callbacks,
  defineJQueryAPI, $fyBuilder,
  createSpaceholder, removed } = require './util'
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
        @$ ?= opts.jquery ? opts.$ ? window?.$
        # init requestAnimationFrame handler
        @animation = new Animation(opts)
        @animation.start()
        # init jquery functions
        @fn = {}
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
        @builder._jquery = @$([])
        @builder._jquery_done = deferred_callbacks()
        do @builder._jquery_done.callback() # builder is allways done
        # override query
        old_query = @builder.query
        @builder.query = (type, tag, key) ->
            return old_query.call(this, type, tag, key) unless tag._jquery?
            if type is 'attr'
                tag._jquery.attr(key)
            else if type is 'text'
                tag._jquery.text()
            else if type is 'tag'
#                 $(key).data('dt-jquery')
                if key._jquery?
                    key
                else
                    # assume this is allready a jquery object
                    if (domel = key[0])?
                        attrs = {}
                        for attr in domel.attributes
                            attrs[attr.name] = attr.value
                        new @builder.Tag domel.nodeName.toLowerCase(), attrs, ->
                            @_jquery = key
                            @end()
                    else
                        old_query.call(this, type, tag, key)
#                     $(key).data('dt-jquery') or {_jquery:key}
        # register ready handler
        @template.register 'ready', (tag, next) ->
            # when tag is already in the dom its fine,
            #  else wait until it is inserted into dom
            if tag._jquery_ready is yes
                next(tag)
            else
                tag._jquery_ready = ->
                    next(tag)

    use: (plugin) ->
        plugin?.call(this, this)
        return this

    listen: () ->
        EVENTS.forEach (event) =>
            @template.on(event, this["on#{event}"].bind(this))

    # flow control : eventlisteners

    onadd: (parent, el) ->
        return if removed el
        if el is el.builder
            el._jquery ?= @$([], el.parent?._jquery)
            $fyBuilder(el)
        else
            el._jquery ?= @$(el.toString(), el.parent._jquery)
            defineJQueryAPI(el)

        that = this
        el._jquery_manip    ?= cancelable_and_retrivable_callbacks()
        el._jquery_done     ?= deferred_callbacks()
        parent._jquery_done ?= deferred_callbacks()
        el._jquery_manip.reset()
        while (cb = el._jquery_manip.callbacks.shift())?
            @animation.push(cb)

        ecb = el._jquery_done.callback()
        pcb = parent._jquery_done.callback()
        if el is el.builder then ecb() else el.ready(ecb)
        if parent is parent.builder then pcb() else parent.ready(pcb)

        el._jquery_insert ?= singlton_callback el, ->
            if @_jquery.length is 0
                createSpaceholder.call(that, this, @parent._jquery)
            that.fn.add(@parent, this)
            if @parent._jquery_wrapped
                @parent._jquery_wrapped = no
                @parent._jquery = @parent._jquery.not(':first') # rm placeholder span
            $fyBuilder(@parent) if @parent is @parent.builder
            @_jquery_ready?()
            @_jquery_ready = yes
            @_jquery_insert = yes
        el._jquery_insert.replace?(el)

        el._jquery_parent_done ?= singlton_callback el, ->
            return if removed this
            if @parent is @parent.builder
                bool = (not @parent.parent? or
                           (@parent.parent is @parent.parent?.builder and # FIXME recursive?
                            @parent.parent?._jquery_insert is true))
                if bool and @parent._jquery_insert is true
                    that.animation.push(@_jquery_insert)
                else
                    @_jquery_insert?()
            else
                that.animation.push(@_jquery_insert)
        el._jquery_parent_done.replace?(el)
        parent._jquery_done(el._jquery_parent_done)

    onreplace: (oldtag, newtag) ->
        return if removed(oldtag) or removed(newtag)
        newtag._jquery_parent_done ?= oldtag._jquery_parent_done
        newtag._jquery_insert      ?= oldtag._jquery_insert
        newtag._jquery_done        ?= oldtag._jquery_done
        oldtag._jquery_parent_done  = null
        oldtag._jquery_insert       = null
        oldtag._jquery_done         = null

        @onadd(oldtag.parent, newtag)

        oldtag._jquery_manip?.cancel?()
        newtag._jquery_manip.reset()
        # if manip left from last time run them
        while (cb = newtag._jquery_manip.callbacks.shift())?
            @animation.push(cb)

        if newtag._jquery_insert is true
            that = this
            newtag._jquery_replace ?= oldtag._jquery_replace
            oldreplacerequest = newtag._jquery_replace?
            newtag._jquery_replace ?= singlton_callback newtag, ->
                if @_jquery.length is 0
                    createSpaceholder.call(that, this, @parent._jquery)
                that.fn.replace(oldtag, this)
                $fyBuilder(this) if this is @builder
            newtag._jquery_replace.replace?(newtag)
            oldtag._jquery_replace = null
            unless oldreplacerequest
                @animation.push(newtag._jquery_replace)

    ontext: (el, text) ->
        el._jquery_manip ?= cancelable_and_retrivable_callbacks(yes)
        @animation.push el._jquery_manip =>
            @fn.text(el, text)

    onraw: (el, html) ->
        el._jquery_manip ?= cancelable_and_retrivable_callbacks(yes)
        @animation.push el._jquery_manip =>
            @fn.raw(el, html)

    onattr: (el, key, value) ->
        el._jquery_manip ?= cancelable_and_retrivable_callbacks(yes)
        @animation.push el._jquery_manip =>
            @fn.attr(el, key, value)

    onshow: (el) ->
        @fn.show(el) if el._jquery?

    onhide: (el) ->
        @fn.hide(el) if el._jquery?

    onremove: (el, opts) ->
        return unless el._jquery?
        @fn.remove(el, opts)
        el._jquery_parent_done_done?.reset()
        el._jquery_done?.reset()
        el._jquery_manip?.cancel()
        delete el._jquery_parent_done
        delete el._jquery_replace
        delete el._jquery_insert
        unless opts.soft
            delete el._jquery_manip
            delete el._jquery_done
            delete el._jquery

    onend: () ->
        @template.jquery = @template._jquery = @builder._jquery
        defineJQueryAPI(@template)


# exports


module.exports = {
    Adapter:BrowserAdapter
    fn:defaultfn
}
