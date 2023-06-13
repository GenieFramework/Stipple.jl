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

function Page(  route::Union{Route,String};
                view::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString,Vector{<:AbstractString},Function},
                model::Union{M,Function,Nothing,Expr,Module} = Stipple.init(EmptyModel),
                layout::Union{Genie.Renderers.FilePath,<:AbstractString,ParsedHTMLString,Nothing,Function} = nothing,
                context::Module = @__MODULE__,
                kwargs...
              ) where {M<:ReactiveModel}

  model = if isa(model, Expr)
            Core.eval(context, model)
          elseif isa(model, Module)
            context = model
            @eval(context, @init())
          end

  view =  if isa(view, ParsedHTMLString) || isa(view, Vector{<:AbstractString})
            string(view)
          elseif isa(view, AbstractString)
            isfile(view) ? filepath(view) : view
          else
            view
          end

  route = isa(route, String) ? Route(; method = GET, path = route) : route
  layout = isa(layout, String) && length(layout) < Stipple.IF_ITS_THAT_LONG_IT_CANT_BE_A_FILENAME && isfile(layout) ? filepath(layout) :
            isa(layout, ParsedHTMLString) || isa(layout, String) ? string(layout) :
              layout

  route.action = () -> (isa(view, Function) ? html! : html)(view; layout, context, model = (isa(model,Function) ? Base.invokelatest(model) : model), kwargs...)

  page = Page(route, view, typeof((isa(model,Function) || isa(model,DataType) ? Base.invokelatest(model) : model)), layout, context)

  if isempty(_pages)
    push!(_pages, page)
  else
    for i in eachindex(_pages)
      if _pages[i].route.path == route.path && _pages[i].route.method == route.method
        Router.delete!(Router.routename(_pages[i].route))
        _pages[i] = page
      else
        push!(_pages, page)
      end
    end
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