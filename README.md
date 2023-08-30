# Bazel Find Mode

An Emacs mode to navigate Bazel projects by finding the definition of labels in
Bazel files.

## Install

### Manually

In order to use this package, first install the bazel mode package:

https://github.com/bazelbuild/emacs-bazel-mode

Then load `bazel-find-mode.el` in your `~/.emacs` with for example:

```elisp
(add-to-list 'load-path (expand-file-name "~/{path/to}/bazel-find-mode"))
(require 'bazel-find-mode)
```

## Usage

Whenever you open a Bazel file (e.g. `BUILD` or `WORKSPACE`), move the cursor on
a label and use the following keybindings:

| Keybinding | Description                                  |
|:-----------|:---------------------------------------------|
| `C-c C-c`  | Copy the absolute label at point             |
| `C-c C-d`  | Jump to the definition of the label at point |


## Contributing

Any contribution is welcome. The requirements are:
* pass the validation of [package-lint](https://github.com/purcell/package-lint)
* byte-compilation without errors or warnings
* no errors with `M-x checkdoc`
