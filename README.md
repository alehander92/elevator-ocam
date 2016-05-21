# elevator

alternate world: elixir/erlang were strongly typed from the beginning?

```ruby
def area_loop:
  receive:
    | Rectangle w h =>
        display "#{w * h}"
    | Circle r =>
        display "#{3.14 * r ** 2}"
    * => area_loop!
  end
end

let pid = spawn: area_loop!
send pid, Rectangle(2, 3)
send pid, Circle(4)
```
