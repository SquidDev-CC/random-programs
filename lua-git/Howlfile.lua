Options:Default "trace"

Tasks:clean()

Tasks:minify "minify" {
  input = "build/clone.lua",
  output = "build/clone.min.lua",
}

Tasks:require "main" (function(spec)
  spec:from "src" {
    include = "*.lua",
  }
  spec:startup "clone"
  spec:output "build/clone.lua"
end)

Tasks:Task "build" { "clean", "minify" } :Description "Main build task"

Tasks:gist "upload" (function(spec)
  spec:summary "A tiny git clone library"
  spec:gist "e0f82765bfdefd48b0b15a5c06c0603b"
  spec:from "build" {
    include = { "clone.lua", "clone.min.lua" }
  }
end) :Requires { "build/clone.lua", "build/clone.min.lua" }


Tasks:Default "build"
