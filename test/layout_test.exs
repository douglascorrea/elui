defmodule Elui.LayoutTest do
  use ExUnit.Case, async: true

  alias Elui.Layout
  alias Elui.Layout.Rect

  @area Rect.new(0, 0, 100, 10)

  describe "vertical layout" do
    test "length constraints" do
      [a, b, c] =
        Layout.vertical([{:length, 3}, {:length, 4}, {:length, 3}])
        |> Layout.split(@area)

      assert a == Rect.new(0, 0, 100, 3)
      assert b == Rect.new(0, 3, 100, 4)
      assert c == Rect.new(0, 7, 100, 3)
    end

    test "excess goes to last segment in legacy mode" do
      [a, b] = Layout.vertical([{:length, 2}, {:length, 2}]) |> Layout.split(@area)
      assert a.height == 2
      assert b.height == 8
    end

    test "fill absorbs remaining space" do
      [a, b, c] =
        Layout.vertical([{:length, 2}, {:fill, 1}, {:length, 2}])
        |> Layout.split(@area)

      assert a.height == 2
      assert b.height == 6
      assert c.height == 2
    end

    test "fill weights are proportional" do
      [a, b] = Layout.vertical([{:fill, 1}, {:fill, 3}]) |> Layout.split(Rect.new(0, 0, 10, 8))
      assert a.height == 2
      assert b.height == 6
    end
  end

  describe "horizontal layout" do
    test "percentage constraints" do
      [a, b] =
        Layout.horizontal([{:percentage, 30}, {:percentage, 70}])
        |> Layout.split(@area)

      assert a.width == 30
      assert b.width == 70
      assert b.x == 30
    end

    test "ratio constraints" do
      [a, b, c] =
        Layout.horizontal([{:ratio, 1, 4}, {:ratio, 1, 4}, {:ratio, 1, 2}])
        |> Layout.split(@area)

      assert a.width == 25
      assert b.width == 25
      assert c.width == 50
    end

    test "min grows to absorb excess" do
      [a, b] = Layout.horizontal([{:min, 10}, {:length, 20}]) |> Layout.split(@area)
      assert a.width == 80
      assert b.width == 20
    end

    test "overflow shrinks proportionally" do
      [a, b] =
        Layout.horizontal([{:length, 80}, {:length, 80}])
        |> Layout.split(@area)

      assert a.width + b.width == 100
    end
  end

  describe "options" do
    test "margin" do
      [only] =
        Layout.vertical([{:fill, 1}], margin: 2)
        |> Layout.split(@area)

      assert only == Rect.new(2, 2, 96, 6)
    end

    test "spacing" do
      [a, b] =
        Layout.horizontal([{:length, 10}, {:length, 10}], spacing: 5)
        |> Layout.split(@area)

      assert a.x == 0
      assert b.x == 15
    end

    test "flex center leaves symmetric whitespace" do
      [a] =
        Layout.horizontal([{:length, 20}], flex: :center)
        |> Layout.split(@area)

      assert a.x == 40
      assert a.width == 20
    end

    test "flex end pushes segments right" do
      [a] = Layout.horizontal([{:length, 20}], flex: :end) |> Layout.split(@area)
      assert a.x == 80
    end

    test "flex space_between" do
      [a, b] =
        Layout.horizontal([{:length, 20}, {:length, 20}], flex: :space_between)
        |> Layout.split(@area)

      assert a.x == 0
      assert b.x == 80
    end
  end

  describe "Rect" do
    test "inner with margin" do
      assert Rect.inner(Rect.new(0, 0, 10, 10), 2) == Rect.new(2, 2, 6, 6)
    end

    test "inner collapses when margin exceeds size" do
      assert Rect.empty?(Rect.inner(Rect.new(0, 0, 3, 3), 2))
    end

    test "intersection and union" do
      a = Rect.new(0, 0, 10, 10)
      b = Rect.new(5, 5, 10, 10)
      assert Rect.intersection(a, b) == Rect.new(5, 5, 5, 5)
      assert Rect.union(a, b) == Rect.new(0, 0, 15, 15)
    end

    test "contains?" do
      r = Rect.new(1, 1, 2, 2)
      assert Rect.contains?(r, {1, 1})
      assert Rect.contains?(r, {2, 2})
      refute Rect.contains?(r, {3, 3})
    end

    test "centered" do
      area = Rect.new(0, 0, 100, 20)
      popup = Rect.centered(area, {:percentage, 50}, {:length, 4})
      assert popup.width == 50
      assert popup.height == 4
      assert popup.x == 25
      assert popup.y == 8
    end
  end
end
