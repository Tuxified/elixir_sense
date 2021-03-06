defmodule ElixirSense.Core.BindingTest do
  use ExUnit.Case, async: true
  alias ElixirSense.Core.Binding
  alias ElixirSense.Core.State.AttributeInfo
  alias ElixirSense.Core.State.VarInfo
  alias ElixirSense.Core.State.ModFunInfo
  alias ElixirSense.Core.State.SpecInfo
  alias ElixirSense.Core.State.StructInfo
  alias ElixirSense.Core.State.TypeInfo

  @env %Binding{}

  describe "expand" do
    test "map" do
      assert {:map, [abc: nil, cde: {:variable, :a}], nil} ==
               Binding.expand(@env, {:map, [abc: nil, cde: {:variable, :a}], nil})
    end

    test "map update" do
      assert {:map, [{:efg, {:atom, :a}}, {:abc, nil}, {:cde, {:variable, :a}}], nil} ==
               Binding.expand(
                 @env,
                 {:map, [abc: nil, cde: {:variable, :a}],
                  {:map, [abc: nil, cde: nil, efg: {:atom, :a}], nil}}
               )
    end

    test "introspection struct" do
      assert {:struct,
              [
                __struct__: {:atom, ElixirSenseExample.ModuleWithTypedStruct},
                other: nil,
                typed_field: nil
              ], ElixirSenseExample.ModuleWithTypedStruct,
              nil} ==
               Binding.expand(
                 @env,
                 {:struct, [], {:atom, ElixirSenseExample.ModuleWithTypedStruct}, nil}
               )
    end

    test "introspection module not a stuct" do
      assert nil ==
               Binding.expand(@env, {:struct, [], {:atom, ElixirSenseExample.EmptyModule}, nil})
    end

    test "introspection struct update" do
      assert {:struct,
              [
                __struct__: {:atom, ElixirSenseExample.ModuleWithTypedStruct},
                other: {:atom, :a},
                typed_field: {:atom, :b}
              ], ElixirSenseExample.ModuleWithTypedStruct,
              nil} ==
               Binding.expand(
                 @env,
                 {:struct, [typed_field: {:atom, :b}],
                  {:atom, ElixirSenseExample.ModuleWithTypedStruct},
                  {:struct, [other: {:atom, :a}],
                   {:atom, ElixirSenseExample.ModuleWithTypedStruct}, nil}}
               )
    end

    test "introspection struct update as map" do
      assert {:struct,
              [
                __struct__: {:atom, ElixirSenseExample.ModuleWithTypedStruct},
                other: {:atom, :a},
                typed_field: {:atom, :b}
              ], ElixirSenseExample.ModuleWithTypedStruct,
              nil} ==
               Binding.expand(
                 @env,
                 {:map, [typed_field: {:atom, :b}],
                  {:struct, [other: {:atom, :a}],
                   {:atom, ElixirSenseExample.ModuleWithTypedStruct}, nil}}
               )
    end

    test "introspection struct from attribute" do
      assert {:struct,
              [
                __struct__: {:atom, ElixirSenseExample.ModuleWithTypedStruct},
                other: nil,
                typed_field: nil
              ], ElixirSenseExample.ModuleWithTypedStruct,
              nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:attributes, [
                   %AttributeInfo{
                     name: :v,
                     type: {:atom, ElixirSenseExample.ModuleWithTypedStruct}
                   }
                 ]),
                 {:struct, [], {:attribute, :v}, nil}
               )
    end

    test "introspection struct from variable" do
      assert {:struct, [__struct__: nil], nil, nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{name: :v, type: {:atom, ElixirSenseExample.ModuleWithTypedStruct}}
                 ]),
                 {:struct, [], {:variable, :v}, nil}
               )
    end

    test "metadata struct" do
      assert {:struct, [__struct__: {:atom, MyMod}, abc: nil], MyMod, nil} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   structs: %{
                     MyMod => %StructInfo{
                       fields: [abc: nil, __struct__: MyMod]
                     }
                   }
                 }),
                 {:struct, [], {:atom, MyMod}, nil}
               )
    end

    test "atom" do
      assert {:atom, :abc} == Binding.expand(@env, {:atom, :abc})
    end

    test "nil" do
      assert nil == Binding.expand(@env, nil)
    end

    test "other" do
      assert nil == Binding.expand(@env, 123)
    end

    test "known variable" do
      assert {:atom, :abc} ==
               Binding.expand(
                 @env |> Map.put(:variables, [%VarInfo{name: :v, type: {:atom, :abc}}]),
                 {:variable, :v}
               )
    end

    test "anonymous variable" do
      assert nil ==
               Binding.expand(
                 @env |> Map.put(:variables, [%VarInfo{name: :_, type: {:atom, :abc}}]),
                 {:variable, :_}
               )
    end

    test "unknown variable" do
      assert nil == Binding.expand(@env, {:variable, :v})
    end

    test "known attribute" do
      assert {:atom, :abc} ==
               Binding.expand(
                 @env |> Map.put(:attributes, [%AttributeInfo{name: :v, type: {:atom, :abc}}]),
                 {:attribute, :v}
               )
    end

    test "unknown attribute" do
      assert nil == Binding.expand(@env, {:attribute, :v})
    end

    test "call existing map field access" do
      assert {:atom, :a} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{name: :map, type: {:map, [field: {:atom, :a}], nil}},
                   %VarInfo{name: :ref, type: {:call, {:variable, :map}, :field, []}}
                 ]),
                 {:variable, :ref}
               )
    end

    test "call existing map field access invalid arity" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{name: :map, type: {:map, [field: {:atom, :a}], nil}},
                   %VarInfo{name: :ref, type: {:call, {:variable, :map}, :field, [nil]}}
                 ]),
                 {:variable, :ref}
               )
    end

    test "call not existing map field access" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{name: :map, type: {:map, [field: {:atom, :a}], nil}},
                   %VarInfo{name: :ref, type: {:call, {:variable, :map}, :not_existing, []}}
                 ]),
                 {:variable, :ref}
               )
    end

    test "call existing struct field access" do
      assert {:atom, :abc} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :map,
                     type:
                       {:struct, [typed_field: {:atom, :abc}],
                        {:atom, ElixirSenseExample.ModuleWithTypedStruct}, nil}
                   },
                   %VarInfo{name: :ref, type: {:call, {:variable, :map}, :typed_field, []}}
                 ]),
                 {:variable, :ref}
               )
    end

    test "call not existing struct field access" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :map,
                     type:
                       {:struct, [typed_field: {:atom, :abc}],
                        {:atom, ElixirSenseExample.ModuleWithTypedStruct}, nil}
                   },
                   %VarInfo{name: :ref, type: {:call, {:variable, :map}, :not_existing, []}}
                 ]),
                 {:variable, :ref}
               )
    end

    test "call existing struct field access invalid arity" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :map,
                     type:
                       {:struct, [typed_field: {:atom, :abc}],
                        {:atom, ElixirSenseExample.ModuleWithTypedStruct}, nil}
                   },
                   %VarInfo{name: :ref, type: {:call, {:variable, :map}, :typed_field, [nil]}}
                 ]),
                 {:variable, :ref}
               )
    end

    test "call on nil" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{name: :ref, type: {:call, nil, :not_existing, []}}
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call not existing fun" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type:
                       {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :not_existing,
                        []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call existing fun invalid arity" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type:
                       {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f1, [nil]}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec t undefined" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f01, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec t expanding to atom" do
      assert {:atom, :asd} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f02, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec t expanding to number" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f03, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec local t expanding to struct" do
      assert {:struct,
              [
                __struct__: {:atom, ElixirSenseExample.FunctionsWithReturnSpec},
                abc: {:map, [key: {:atom, nil}], nil}
              ], ElixirSenseExample.FunctionsWithReturnSpec,
              nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f1, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec remote t expanding to struct" do
      assert {:struct,
              [__struct__: {:atom, ElixirSenseExample.FunctionsWithReturnSpec.Remote}, abc: nil],
              ElixirSenseExample.FunctionsWithReturnSpec.Remote,
              nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f3, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec struct" do
      assert {:struct,
              [__struct__: {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, abc: nil],
              ElixirSenseExample.FunctionsWithReturnSpec,
              nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f5, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec local t expanding to map" do
      assert {:map, [{:abc, {:atom, :asd}}, {:cde, {:atom, :asd}}], nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f2, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec remote t expanding to map" do
      assert {:map, [abc: nil], nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f4, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec map" do
      assert {:map, [abc: nil], nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f6, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec intersection different returns" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f7, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec intersection same returns" do
      assert {:map, [abc: nil], nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type:
                       {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f71, [nil]}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec union" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f8, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with spec parametrized map" do
      assert {:map, [abc: nil], nil} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f91, []}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "local call metadata fun returning struct" do
      assert {:struct, [{:__struct__, {:atom, MyMod}}, {:abc, nil}], MyMod, nil} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{name: :ref, type: {:local_call, :fun, []}}
                   ],
                   current_module: MyMod,
                   specs: %{
                     {MyMod, :fun, nil} => %SpecInfo{
                       specs: ["@spec fun() :: %MyMod{}"]
                     },
                     {MyMod, :fun, 0} => %SpecInfo{
                       specs: ["@spec fun() :: %MyMod{}"]
                     }
                   },
                   mods_and_funs: %{
                     {MyMod, :fun, nil} => %ModFunInfo{
                       params: [[]],
                       type: :defp
                     }
                   },
                   structs: %{
                     MyMod => %StructInfo{
                       fields: [abc: nil, __struct__: MyMod]
                     }
                   }
                 }),
                 {:variable, :ref}
               )
    end

    test "local call metadata fun returning local type expanding to struct" do
      assert {:struct, [{:__struct__, {:atom, MyMod}}, {:abc, nil}], MyMod, nil} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{name: :ref, type: {:local_call, :fun, []}}
                   ],
                   current_module: MyMod,
                   specs: %{
                     {MyMod, :fun, nil} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     },
                     {MyMod, :fun, 0} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     }
                   },
                   mods_and_funs: %{
                     {MyMod, :fun, nil} => %ModFunInfo{
                       params: [[]],
                       type: :def
                     }
                   },
                   structs: %{
                     MyMod => %StructInfo{
                       fields: [abc: nil, __struct__: MyMod]
                     }
                   },
                   types: %{
                     {MyMod, :t, nil} => %TypeInfo{
                       specs: ["@type t() :: %MyMod{}"]
                     },
                     {MyMod, :t, 0} => %TypeInfo{
                       specs: ["@type t() :: %MyMod{}"]
                     }
                   }
                 }),
                 {:variable, :ref}
               )
    end

    test "local call metadata fun returning local type expanding to private type" do
      assert {:struct, [{:__struct__, {:atom, MyMod}}, {:abc, nil}], MyMod, nil} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{name: :ref, type: {:local_call, :fun, []}}
                   ],
                   current_module: MyMod,
                   specs: %{
                     {MyMod, :fun, nil} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     },
                     {MyMod, :fun, 0} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     }
                   },
                   mods_and_funs: %{
                     {MyMod, :fun, nil} => %ModFunInfo{
                       params: [[]],
                       type: :def
                     }
                   },
                   structs: %{
                     MyMod => %StructInfo{
                       fields: [abc: nil, __struct__: MyMod]
                     }
                   },
                   types: %{
                     {MyMod, :t, nil} => %TypeInfo{
                       kind: :typep,
                       specs: ["@type t() :: %MyMod{}"]
                     },
                     {MyMod, :t, 0} => %TypeInfo{
                       kind: :typep,
                       specs: ["@type t() :: %MyMod{}"]
                     }
                   }
                 }),
                 {:variable, :ref}
               )
    end

    test "remote call metadata public fun returning local type expanding to struct" do
      assert {:struct, [{:__struct__, {:atom, MyMod}}, {:abc, nil}], MyMod, nil} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{name: :ref, type: {:call, {:atom, MyMod}, :fun, []}}
                   ],
                   current_module: SomeMod,
                   specs: %{
                     {MyMod, :fun, nil} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     },
                     {MyMod, :fun, 0} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     }
                   },
                   mods_and_funs: %{
                     {MyMod, :fun, nil} => %ModFunInfo{
                       params: [[]],
                       type: :def
                     }
                   },
                   structs: %{
                     MyMod => %StructInfo{
                       fields: [abc: nil, __struct__: MyMod]
                     }
                   },
                   types: %{
                     {MyMod, :t, nil} => %TypeInfo{
                       specs: ["@type t() :: %MyMod{}"]
                     },
                     {MyMod, :t, 0} => %TypeInfo{
                       specs: ["@type t() :: %MyMod{}"]
                     }
                   }
                 }),
                 {:variable, :ref}
               )
    end

    test "remote call metadata public fun returning local type expanding to opaque" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{name: :ref, type: {:call, {:atom, MyMod}, :fun, []}}
                   ],
                   current_module: SomeMod,
                   specs: %{
                     {MyMod, :fun, nil} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     },
                     {MyMod, :fun, 0} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     }
                   },
                   mods_and_funs: %{
                     {MyMod, :fun, nil} => %ModFunInfo{
                       params: [[]],
                       type: :def
                     }
                   },
                   structs: %{
                     MyMod => %StructInfo{
                       fields: [abc: nil, __struct__: MyMod]
                     }
                   },
                   types: %{
                     {MyMod, :t, nil} => %TypeInfo{
                       kind: :opaque,
                       specs: ["@type t() :: %MyMod{}"]
                     },
                     {MyMod, :t, 0} => %TypeInfo{
                       kind: :opaque,
                       specs: ["@type t() :: %MyMod{}"]
                     }
                   }
                 }),
                 {:variable, :ref}
               )
    end

    test "remote call metadata private fun returning local type expanding to struct" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{name: :ref, type: {:call, {:atom, MyMod}, :fun, []}}
                   ],
                   current_module: SomeMod,
                   specs: %{
                     {MyMod, :fun, nil} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     },
                     {MyMod, :fun, 0} => %SpecInfo{
                       specs: ["@spec fun() :: t()"]
                     }
                   },
                   mods_and_funs: %{
                     {MyMod, :fun, nil} => %ModFunInfo{
                       params: [[]],
                       type: :defp
                     }
                   },
                   structs: %{
                     MyMod => %StructInfo{
                       fields: [abc: nil, __struct__: MyMod]
                     }
                   },
                   types: %{
                     {MyMod, :t, nil} => %TypeInfo{
                       specs: ["@type t() :: %MyMod{}"]
                     },
                     {MyMod, :t, 0} => %TypeInfo{
                       specs: ["@type t() :: %MyMod{}"]
                     }
                   }
                 }),
                 {:variable, :ref}
               )
    end

    test "local call metadata fun with default args returning struct" do
      env =
        @env
        |> Map.merge(%{
          current_module: MyMod,
          specs: %{
            {MyMod, :fun, nil} => %SpecInfo{
              specs: ["@spec fun(integer(), integer(), any()) :: %MyMod{}"]
            },
            {MyMod, :fun, 3} => %SpecInfo{
              specs: ["@spec fun(integer(), integer(), any()) :: %MyMod{}"]
            }
          },
          mods_and_funs: %{
            {MyMod, :fun, nil} => %ModFunInfo{
              params: [
                [
                  {:\\, [], []},
                  {:\\, [], []},
                  {:x, [], []}
                ]
              ],
              type: :def
            }
          },
          structs: %{
            MyMod => %StructInfo{
              fields: [abc: nil, __struct__: MyMod]
            }
          }
        })

      assert nil ==
               Binding.expand(
                 env
                 |> Map.put(:variables, [
                   %VarInfo{name: :ref, type: {:local_call, :fun, []}}
                 ]),
                 {:variable, :ref}
               )

      assert {:struct, [{:__struct__, {:atom, MyMod}}, {:abc, nil}], MyMod, nil} ==
               Binding.expand(
                 env
                 |> Map.put(:variables, [
                   %VarInfo{name: :ref, type: {:local_call, :fun, [nil]}}
                 ]),
                 {:variable, :ref}
               )

      assert {:struct, [{:__struct__, {:atom, MyMod}}, {:abc, nil}], MyMod, nil} ==
               Binding.expand(
                 env
                 |> Map.put(:variables, [
                   %VarInfo{name: :ref, type: {:local_call, :fun, [nil, nil]}}
                 ]),
                 {:variable, :ref}
               )

      assert {:struct, [{:__struct__, {:atom, MyMod}}, {:abc, nil}], MyMod, nil} ==
               Binding.expand(
                 env
                 |> Map.put(:variables, [
                   %VarInfo{name: :ref, type: {:local_call, :fun, [nil, nil, nil]}}
                 ]),
                 {:variable, :ref}
               )

      assert nil ==
               Binding.expand(
                 env
                 |> Map.put(:variables, [
                   %VarInfo{name: :ref, type: {:local_call, :fun, [nil, nil, nil, nil]}}
                 ]),
                 {:variable, :ref}
               )
    end

    test "remote call fun with default args" do
      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type: {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f10, []}
                   }
                 ]),
                 {:variable, :ref}
               )

      assert {:atom, String} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type:
                       {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f10, [nil]}
                   }
                 ]),
                 {:variable, :ref}
               )

      assert {:atom, String} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type:
                       {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f10,
                        [nil, nil]}
                   }
                 ]),
                 {:variable, :ref}
               )

      assert {:atom, String} ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type:
                       {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f10,
                        [nil, nil, nil]}
                   }
                 ]),
                 {:variable, :ref}
               )

      assert nil ==
               Binding.expand(
                 @env
                 |> Map.put(:variables, [
                   %VarInfo{
                     name: :ref,
                     type:
                       {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f10,
                        [nil, nil, nil, nil]}
                   }
                 ]),
                 {:variable, :ref}
               )
    end

    test "local call imported fun with spec t expanding to atom" do
      assert {:atom, :asd} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{name: :ref, type: {:local_call, :f02, []}}
                   ],
                   imports: [ElixirSenseExample.FunctionsWithReturnSpec]
                 }),
                 {:variable, :ref}
               )
    end

    test "local call no parens imported fun with spec t expanding to atom" do
      assert {:atom, :asd} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{name: :ref, type: {:variable, :f02}}
                   ],
                   imports: [ElixirSenseExample.FunctionsWithReturnSpec]
                 }),
                 {:variable, :ref}
               )
    end

    test "extract struct key type from typespec" do
      assert {:map, [key: {:atom, nil}], nil} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{
                       name: :ref,
                       type:
                         {:call,
                          {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f1, []},
                          :abc, []}
                     }
                   ],
                   imports: [ElixirSenseExample.FunctionsWithReturnSpec]
                 }),
                 {:variable, :ref}
               )
    end

    test "extract required map key type from typespec" do
      assert {:atom, :asd} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{
                       name: :ref,
                       type:
                         {:call,
                          {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f2, []},
                          :abc, []}
                     }
                   ],
                   imports: [ElixirSenseExample.FunctionsWithReturnSpec]
                 }),
                 {:variable, :ref}
               )
    end

    test "optimistically extract optional map key type from typespec" do
      assert {:atom, :asd} ==
               Binding.expand(
                 @env
                 |> Map.merge(%{
                   variables: [
                     %VarInfo{
                       name: :ref,
                       type:
                         {:call,
                          {:call, {:atom, ElixirSenseExample.FunctionsWithReturnSpec}, :f2, []},
                          :cde, []}
                     }
                   ],
                   imports: [ElixirSenseExample.FunctionsWithReturnSpec]
                 }),
                 {:variable, :ref}
               )
    end
  end

  describe "Map functions" do
    test "put" do
      assert {:map, [cde: {:atom, :b}, abc: {:atom, :a}], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :put,
                  [{:map, [abc: {:atom, :a}], nil}, {:atom, :cde}, {:atom, :b}]}
               )
    end

    test "put not a map" do
      assert {:map, [cde: {:atom, :b}], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :put, [nil, {:atom, :cde}, {:atom, :b}]}
               )
    end

    test "put not an atom key" do
      assert {:map, [], nil} =
               Binding.expand(@env, {:call, {:atom, Map}, :put, [nil, nil, {:atom, :b}]})
    end

    test "delete" do
      assert {:map, [abc: {:atom, :a}], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :delete,
                  [{:map, [abc: {:atom, :a}, cde: nil], nil}, {:atom, :cde}]}
               )
    end

    test "merge" do
      assert {:map, [abc: {:atom, :a}, cde: {:atom, :b}], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :merge,
                  [{:map, [abc: {:atom, :a}], nil}, {:map, [cde: {:atom, :b}], nil}]}
               )
    end

    test "merge/3" do
      assert {:map, [abc: {:atom, :a}, cde: {:atom, :b}], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :merge,
                  [{:map, [abc: {:atom, :a}], nil}, {:map, [cde: {:atom, :b}], nil}, nil]}
               )
    end

    test "from_struct" do
      assert {:map, [other: nil, typed_field: nil], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :from_struct,
                  [{:struct, [], {:atom, ElixirSenseExample.ModuleWithTypedStruct}, nil}]}
               )
    end

    test "from_struct atom arg" do
      assert {:map, [other: nil, typed_field: nil], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :from_struct,
                  [{:atom, ElixirSenseExample.ModuleWithTypedStruct}]}
               )
    end

    test "update" do
      assert {:map, [abc: nil], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :update,
                  [{:map, [abc: {:atom, :a}], nil}, {:atom, :abc}, nil, {:atom, :b}]}
               )
    end

    test "update!" do
      assert {:map, [abc: nil], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :update!,
                  [{:map, [abc: {:atom, :a}], nil}, {:atom, :abc}, {:atom, :b}]}
               )
    end

    test "replace!" do
      assert {:map, [abc: {:atom, :b}], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :replace!,
                  [{:map, [abc: {:atom, :a}], nil}, {:atom, :abc}, {:atom, :b}]}
               )
    end

    test "put_new" do
      assert {:map, [cde: {:atom, :b}, abc: {:atom, :a}], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :put_new,
                  [{:map, [abc: {:atom, :a}], nil}, {:atom, :cde}, {:atom, :b}]}
               )
    end

    test "put_new_lazy" do
      assert {:map, [cde: nil, abc: {:atom, :a}], nil} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :put_new_lazy,
                  [{:map, [abc: {:atom, :a}], nil}, {:atom, :cde}, {:atom, :b}]}
               )
    end

    test "fetch!" do
      assert {:atom, :a} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :fetch!, [{:map, [abc: {:atom, :a}], nil}, {:atom, :abc}]}
               )
    end

    test "fetch" do
      assert {:atom, :a} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :fetch, [{:map, [abc: {:atom, :a}], nil}, {:atom, :abc}]}
               )
    end

    test "get" do
      assert {:atom, :a} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :get, [{:map, [abc: {:atom, :a}], nil}, {:atom, :abc}]}
               )
    end

    test "get default" do
      assert {:atom, :x} =
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :get,
                  [{:map, [abc: {:atom, :a}], nil}, {:atom, :cde}, {:atom, :x}]}
               )
    end

    test "get_lazy" do
      assert nil ==
               Binding.expand(
                 @env,
                 {:call, {:atom, Map}, :get_lazy,
                  [{:map, [abc: {:atom, :a}], nil}, {:atom, :cde}, {:atom, :x}]}
               )
    end

    test "new" do
      assert {:map, [], nil} = Binding.expand(@env, {:call, {:atom, Map}, :new, []})
    end
  end
end
