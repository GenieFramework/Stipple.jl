# attribute testing

@testitem "Flexgrid attributes for row(), column(), and cell()" setup=[StippleTestSetup] begin

    el = column(col = 2, sm = 9, class = "myclass")
    @test contains(el, "class=\"myclass column col-2 col-sm-9")

    el = column(col = 2, sm = 9, class = :myclass)
    @test contains(el, ":class=\"[myclass,'column','col-2','col-sm-9']\"")

    el = column(col = 2, sm = 9, class! = "myclass")
    @test contains(el, ":class=\"[myclass,'column','col-2','col-sm-9']\"")

    el = column(col = 2, sm = 9, class! = :myclass)
    @test contains(el, ":class=\"[myclass,'column','col-2','col-sm-9']\"")

    # ---------

    el = row(col = 2, sm = 9, class = "myclass")
    @test contains(el, "class=\"myclass row col-2 col-sm-9")

    el = row(col = 2, sm = 9, class = :myclass)
    @test contains(el, ":class=\"[myclass,'row','col-2','col-sm-9']\"")

    el = row(col = 2, sm = 9, class! = "myclass")
    @test contains(el, ":class=\"[myclass,'row','col-2','col-sm-9']\"")

    # ---------

    el = cell(col = 2, sm = 9, class = "myclass")
    @test contains(el, "class=\"myclass st-col col-2 col-sm-9")

    el = cell(col = 2, sm = 9, class = :myclass)
    @test contains(el, ":class=\"[myclass,'st-col','col-2','col-sm-9']\"")

    el = column(col = 2, sm = 9, class! = "myclass")
    @test contains(el, ":class=\"[myclass,'column','col-2','col-sm-9']\"")

    @test cell(sm = 9) == "<div class=\"st-col col col-sm-9\"></div>"

    @test cell(col = -1, sm = 9) == "<div class=\"st-col col-sm-9\"></div>"

    @test htmldiv(col = 9, class = "a b c") == "<div class=\"a b c col-9\"></div>"

    @test htmldiv(col = 9, class = split("a b c")) == "<div :class=\"['a','b','c','col-9']\"></div>"

    @test htmldiv(col = 9, class = Dict(:myclass => "b"), class! = "test") == "<div :class=\"[test,{'myclass':b},'col-9']\"></div>"

    @test row(@gutter :sm [
        cell("Hello", sm = 2,  md = 8)
        cell("World", sm = 10, md = 4)
    ]).data == "<div class=\"row q-col-gutter-sm\"><div class=\"col col-sm-2 col-md-8\">" *
    "<div class=\"st-col\">Hello</div></div><div class=\"col col-sm-10 col-md-4\"><div class=\"st-col\">World</div></div></div>"
end

@testitem "Vue Conditionals and Iterator" setup=[StippleTestSetup] begin
    el = column("Hello", @if(:visible))
    @test contains(el, "v-if=\"visible\"")

    el = column("Hello", @else)
    @test contains(el, "v-else")

    el = column("Hello", @elseif(:visible))
    @test contains(el, "v-else-if=\"visible\"")

    el = row(@showif("n > 0"), "The result is '{{ n }}'")
    @test el == "<div v-show=\"n > 0\" class=\"row\">The result is '{{ n }}'</div>"

    el = row(@for("i in [1, 2, 3, 4, 5]"), "{{ i }}")
    @test contains(el, "v-for=\"i in [1, 2, 3, 4, 5]\"")
    
    el = row(@for(:i in 1:5), "{{ i }}")
    @test contains(el, "v-for=\"i in [1,2,3,4,5]\"")

    el = row(@for(i in 1:5), "{{ i }}")
    @test contains(el, "v-for=\"i in [1,2,3,4,5]\"")

    el = htmldiv(@for i in :my_js_variable)
    @test contains(el, "v-for=\"i in my_js_variable\"")

    el = ul(li("k: {{ k }}, v: {{ v }}, i: {{ i }}", @for((:v, :k, :i) in OrderedDict("a" => "A", "b" => "B"))))
    @test contains(el, "v-for=\"(v,k,i) in {'a':'A','b':'B'}\"")

    el = ul(li("k: {{ k }}, v: {{ v }}, i: {{ i }}", @for((v, k, i) in OrderedDict("a" => "A", "b" => "B"))))
    @test contains(el, "v-for=\"(v,k,i) in {'a':'A','b':'B'}\"")

    # test Julia expressions
    el = row(@showif(:n > 0), "The result is '{{ n }}'")
    @test el == "<div v-show=\"n > 0\" class=\"row\">The result is '{{ n }}'</div>"

    el =  row("hello", @showif(:n^2 ∉ 3:2:11))
    @test el == "<div v-show=\"!((n ** 2) in [3,5,7,9,11])\" class=\"row\">hello</div>"

    fruit = apple

    el = row(@showif(:fruit == apple), "My fruit is a(n) '{{ fruit }}'")
    @test el == "<div v-show=\"fruit == 'apple'\" class=\"row\">My fruit is a(n) '{{ fruit }}'</div>"
end

@testitem "Javascript expressions: JSExpr" setup=[StippleTestSetup] begin
    # note, you cannot compare a JSExpr by `==` directly as `==` is overloaded for JSExpr
    je1 = @jsexpr(:x+1)
    je2 = @jsexpr(:y+2)
    @test Stipple.json(je1 == je2) == "(x + 1) == (y + 2)"

    je1 = @jsexpr(2 * :xx^2 + 2)
    @test Stipple.json(je1) == "(2 * (xx ** 2)) + 2"

    je2 = @jsexpr(:y + '2')
    @test Stipple.json(je2) == "y + '2'"

    @test Stipple.json(je1 * je2) == "((2 * (xx ** 2)) + 2) * (y + '2')"
    @test Stipple.json(je1 + je2) == "((2 * (xx ** 2)) + 2) + (y + '2')"
end