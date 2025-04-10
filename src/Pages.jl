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

function add_page!(pages::Vector{Page}, page::Page; clear_routes::Bool = false)
  if isempty(pages)
    push!(pages, page)
  else
    replaced = false
    for i in reverse(eachindex(pages))
      if pages[i].route.path == page.route.path && pages[i].route.method == page.route.method
        # if already replaced then delete the duplicate
        replaced && deleteat!(pages, i)
        clear_routes && Router.delete!(Router.routename(pages[i].route))
        pages[i] = page
        replaced = true
      end
    end
    replaced || push!(pages, page)
  end

  return page
end

function Page(  route::Union{Route,String};
                view::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString,Vector{<:AbstractString},Function},
                model::Union{M,Function,Nothing,Expr,Module,Type{M}} = Stipple.init(EmptyModel),
                layout::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString,Nothing,Function} = nothing,
                context::Module = @__MODULE__,
                debounce::Int = Stipple.JS_DEBOUNCE_TIME,
                throttle::Int = Stipple.JS_THROTTLE_TIME,
                transport::Module = Stipple.WEB_TRANSPORT[],
                core_theme::Bool = true,
                pre::Union{Function, Vector{<:Function}} = Function[],
                post::Union{Function, Vector{<:Function}} = Function[],
                kwargs...
              ) where {M<:ReactiveModel}

  model isa Expr && (model = @eval context model)
  # assert that model is a ReactiveModel and not a Module, because GenieBuilder assumes that
  model isa Module && (model = @eval context Stipple.@type())
  view = if isa(view, Function) || isa(view, ParsedHTMLString)
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

  layout = if isa(layout, String) && length(layout) < Stipple.IF_ITS_THAT_LONG_IT_CANT_BE_A_FILENAME && isfile(layout)
    filepath(layout)
  elseif isa(layout, ParsedHTMLString) || isa(layout, String)
    string(layout)
  else
    layout
  end

  page = Page(route, view, model, layout, context)

  pre isa Function && (pre = [pre])
  post isa Function && (post = [post])
  
  route.action = function ()
    for f in pre
      result = f()
      result !== nothing && return result
    end
    model = if page.model isa DataType && page.model <: ReactiveModel || page.model isa Module
      Stipple.ReactiveTools.init_model(page.model; debounce, throttle, transport, core_theme)
    else
      page.model
    end
    for f in post
      result = f(model)
      result !== nothing && return result
    end

    page_fn = view isa Function ? html! : html
    page_fn(view; layout, context, model = model, kwargs...)
  end

  add_page!(_pages, page)

  Router.route(route)

  page
end

function Base.delete!(page::Page)
  deleteat!(_pages, findall(p -> p == page, _pages))
end

function remove_pages()
  empty!(_pages)
end

function Genie.route(p::Stipple.Pages.Page)
  p ∈ Stipple.Pages._pages || push!(Stipple.Pages._pages, p)
  route(p.route)
end

end
