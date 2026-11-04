# nvim: no debugger

**Ruling** [USER 2026-11-04]: dap, dap-ui, dap-lldb and the codelldb adapter are
out of nvim. `vscode-lldb` alone held 1.4 GiB of the closure, through
lldb -> clang and LLVM libraries, and no debug keymaps were ever configured.
rustaceanvim stays for its LSP handling; `:RustLsp debuggables` no longer works.

**Revisit if**: debugging from inside nvim becomes a real need. Keeping codelldb
out of the closure by taking it from the project's devshell would be the first
thing to try.
