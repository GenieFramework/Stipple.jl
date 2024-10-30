"""
Utility functions for working with themes.
"""
module Theme

using Genie
using Stipple

"""
A dictionary of themes. Each theme is a string that represents a CSS class.
Add your own themes here.
"""
const THEMES = Dict{Symbol, String}(
	:default => "theme-default-light",
)


"""
The current theme.
"""
const CURRENT_THEME = Ref(:default)


"""
Stores the index of the theme in Stipple.Layout.THEMES[]
"""
const THEME_INDEX = Ref(0) #TODO: this will need to be refactored to manage themes in a dict by name -- but it will be breaking


"""
Get the current theme.
"""
function set_theme(theme::Symbol)
	if haskey(THEMES, theme)
		CURRENT_THEME[] = theme
	else
		error("Theme not found: $theme")
	end
end


"""
Get the current theme.
"""
function get_theme()
  return CURRENT_THEME[]
end


function register_theme(name::Symbol, theme::String)
  THEMES[name] = theme
end


"""
Get the current theme as a stylesheet to be loaded into Stipple.Layout.THEMES[]
"""
function to_asset(theme::Symbol = CURRENT_THEME[]) :: Function
  theme_path = if haskey(THEMES, theme)
    THEMES[theme]
  else
    error("Theme not found: $theme")
  end

  return if startswith(theme_path, "http://") || startswith(theme_path, "https://") || startswith(theme_path, "/")
    () -> stylesheet(theme_path)
  else
    () -> stylesheet(Genie.Assets.asset_path(Stipple.assets_config, :css, file=theme_path))
  end
end

end
