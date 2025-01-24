"""
Utility module to help define pages (dashboards) as bundles of route, view and model.
"""
module Pages

using Genie.Router
import Genie.Router: Route

using Genie.Renderers
using Genie.Renderers.Html
using Stipple

export Page
export pages
export routehandler

@vars EmptyModel begin
end

mutable struct Page
  route::Route
  view::Union{Genie.Renderers.FilePath,Function,<:AbstractString}
  model
  layout::Union{Genie.Renderers.FilePath,Function,<:AbstractString,Nothing}
  context::Module
end

const _pages = Page[]
pages() = _pages

routehandler(model::ReactiveModel, ::Any) = routehandler(model)
routehandler(::ReactiveModel) = nothing

function Page(  route::Union{Route,String};
                view::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString,Vector{<:AbstractString},Function},
                model::Union{M,Function,Nothing,Expr,Module,Type{M}} = Stipple.init(EmptyModel),
                layout::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString,Nothing,Function} = nothing,
                context::Module = @__MODULE__,
                debounce::Int = Stipple.JS_DEBOUNCE_TIME,
                throttle::Int = Stipple.JS_THROTTLE_TIME,
                transport::Module = Stipple.WEB_TRANSPORT[],
                core_theme::Bool = true,
                kwargs...
              ) where {M<:ReactiveModel}

  routepath = Symbol(route isa Route ? route.path : route)
  model = if isa(model, Expr)
            Core.eval(context, model)
          elseif isa(model, Module)
            context = model
            () -> Stipple.ReactiveTools.init_model(context; debounce, throttle, transport, core_theme)
          elseif model isa DataType
            # as model is being redefined, we need to create a copy
            mymodel = model
            () -> Stipple.ReactiveTools.init_model(mymodel; debounce, throttle, transport, core_theme)
          else
            model
          end
  view =  if isa(view, Function) || isa(view, ParsedHTMLString)
            view
          elseif isa(view, Vector{ParsedHTMLString})
            ParsedHTMLString(view)
          elseif isa(view, Vector{<:AbstractString})
            join(view)
          elseif isa(view, AbstractString)
            isfile(view) ? filepath(view) : view
          else
            view
          end

  route = isa(route, String) ? Route(; method = GET, path = route) : route
  layout = isa(layout, String) && length(layout) < Stipple.IF_ITS_THAT_LONG_IT_CANT_BE_A_FILENAME && isfile(layout) ? filepath(layout) :
            isa(layout, ParsedHTMLString) || isa(layout, String) ? string(layout) :
              layout

  route.action = function ()
    model = model isa Function ? Base.invokelatest(model) : model
    page = view isa Function ? html! : html
    result = routehandler(model, Val(routepath))
    result !== nothing && return result
    page(view; layout, context, model, kwargs...)
  end

  page = Page(route, view, model, layout, context)

  if isempty(_pages)
    push!(_pages, page)
  else
    new_page = true
    replaced = false
    for i in reverse(eachindex(_pages))
      if _pages[i].route.path == route.path && _pages[i].route.method == route.method
        # if already replaced then delete the duplicate
        replaced && deleteat!(_pages, i)
        Router.delete!(Router.routename(_pages[i].route))
        _pages[i] = page
        new_page = false
        replaced = true
      end
    end
    new_page && push!(_pages, page)
  end

  Router.route(route)

  page
end

function Base.delete!(page::Page)
  deleteat!(_pages, findall(p -> p == page, _pages))
end

function remove_pages()
  empty!(_pages)
end

end
