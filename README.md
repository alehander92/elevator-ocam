# elevator

alternate world: elixir/erlang were strongly typed from the beginning?

```ruby
-> area_loop:
  | Rectangle w h => display("#{w * h}")
  | Circle r      => display("#{3.14 * r ** 2}")
end

let pid = spawn([(x) -> area_loop()])
pid <- Rectangle(2 3)
pid <- Circle(4)
```
