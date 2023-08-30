;;; bazel-find-mode.el --- Additions to bazel-mode    -*- lexical-binding: t; -*-

;; Copyright (C) 2023  Marco Vocialta

;; Author: Marco Vocialta <macurovc@tutanota.com>
;; Package-Requires: ((emacs "28.1"))
;; URL: https://github.com/macurovc/bazel-find-mode
;; Version: 1.0

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package helps finding the definition of labels in Bazel files.
;; In order to use it, first install the bazel mode package:

;; https://github.com/bazelbuild/emacs-bazel-mode

;; Then load this file in your ~/.emacs with for example:

;; (load "~/.emacs.d/private/bazel-find-mode.el")

;; Whenever you open a Bazel file (e.g. BUILD or WORKSPACE), move the
;; cursor on a label and use the following keybindings:

;; C-c C-c: to copy the absolute label at point
;; C-c C-d: jump to the definition of the label at point

;;; Code:

(require 'bazel)

(defgroup bazel-find nil "Bazel Find Mode custom variables."
  :group 'convenience)

(defcustom bazel-find--project-dirs
  '()
  "Association list containing the paths to external projects.
For example: ((\"project\" . \"path/to/project\"))"
  :group 'bazel-find
  :type 'alist)

(defun bazel-find--find-workspace-root-from (dir)
  "Find workspace root directory.
Argument DIR directory from which the search for the root starts."
  (if (or (file-exists-p (file-name-concat dir "WORKSPACE"))
          (equal dir "/"))
      dir
    (bazel-find--find-workspace-root-from (file-name-directory (directory-file-name dir)))))

(defun bazel-find--workspace-root ()
  "Find workspace root directory."
  (bazel-find--find-workspace-root-from (bazel-find--current-dir)))

(defun bazel-find--target-at-point ()
  "Return the label of the target at point."
  (save-excursion (search-backward "\"")
                  (re-search-forward (rx (group (+ (not "\"")))))
                  (match-string 1)))

(defun bazel-find--current-dir ()
  "Return directory of buffer."
  (file-name-directory (buffer-file-name)))

(defun bazel-find--yank-label-at-point ()
  "Add bazel target under point to kill ring."
  (interactive)
  (when-let* ((label (bazel-find--target-at-point))
              (dir (bazel-find--current-dir))
              (relative-dir (f-relative dir (bazel-find--workspace-root))))
    (kill-new (message  "//%s:%s" (directory-file-name relative-dir) label))))


(defun bazel-find--find-project-location (project)
  "Find the location of a PROJECT with bazel query."
  (with-temp-buffer
    (let* ((program (car bazel-command))
           (label (format "//external:%s" project))
           (exit-code (call-process program nil (current-buffer) nil "query" "--output=build" label)))
      (if (= exit-code 0)
          (progn
            (re-search-backward (rx (seq "path = \"" (group (* not-newline)) "\"")))
            (match-string 1))
        (error "Couldn't run \"%s\": %s" (car bazel-command) (buffer-string))))))


(defun bazel-find--lookup-project-location (project)
  "Check if PROJECT location is stored and derive it via Bazel otherwise."
  (let ((cached-dir (cdr (assoc project bazel-find--project-dirs))))
    (if cached-dir (car cached-dir)
      (let* ((project-dir (bazel-find--find-project-location project))
             (dir (if (file-name-absolute-p project-dir) project-dir
                    (expand-file-name (file-name-concat (bazel-find--workspace-root) project-dir)))))
        (push (list project dir) bazel-find--project-dirs)
        dir))))


(defun bazel-find--project-dir-for (path)
  "Get the project directory for the base directory of a target.
Argument PATH Bazel path component of a target name."
  (if (string-empty-p path)
      (bazel-find--current-dir)
    (let* ((split (split-string path "//"))
           (project (string-trim-left (car split) "@"))
           (dir (car (cdr split)))
           (project-location (unless (string-empty-p project) (bazel-find--lookup-project-location project))))
      (if project-location
          (file-name-concat project-location dir)
        (file-name-concat (bazel-find--workspace-root) dir)))))


(defun bazel-find--open-if-file (file)
  "Open a FILE if it exists and it isn't a directory."
  (when (and (file-exists-p file) (not (file-directory-p file)))
    (xref-push-marker-stack)
    (find-file file)))


(defun bazel-find--is-loaded-rule-at-point ()
  "Is there a rule from a load statement at point."
  (let ((label (bazel-find--target-at-point)))
    (and (not (string-search "/" label))
         (save-excursion
           (search-backward "(")
           (string-equal "load" (buffer-substring (- (point) 4) (point)))))))


(defun bazel-find--find-target-at-point ()
  "Find target at point."
  (let ((label (bazel-find--target-at-point)))
    (unless (bazel-find--open-if-file label)
      (let* ((split-label (split-string label ":"))
             (path (car split-label))
             (file (car (cdr split-label)))
             (base-dir (bazel-find--project-dir-for path))
             (basic-build-file (file-name-concat base-dir "BUILD"))
             (build-file (if (file-exists-p basic-build-file)
                             basic-build-file (concat basic-build-file ".bazel")))
             (open-candidate (file-name-concat base-dir file)))
        (cond ((bazel-find--open-if-file open-candidate) t)
              ((file-exists-p build-file)
               (xref-push-marker-stack)
               (find-file build-file)
               (goto-char (point-max))
               (let ((name (file-name-nondirectory (or file path))))
                 (or (re-search-backward (format "name.*=.*\"%s\"" name) nil t)
                   (search-backward name))))
              (t (error "Cannot locate %s" label)))))))


(defun bazel-find--set-keybindings ()
  "Set the keybindings for this mode."
  (local-set-key (kbd "C-c C-c") 'bazel-find--yank-label-at-point)
  (local-set-key (kbd "C-c C-d") 'bazel-find--find-label-at-point))


(defun bazel-find--find-label-at-point ()
  "Find label at point."
  (interactive)
  (let ((label (bazel-find--target-at-point)))
    (if (bazel-find--is-loaded-rule-at-point)
        (progn
          (search-backward "(")
          (search-forward "\"")
          (forward-char)
          (bazel-find--find-target-at-point)
          (goto-char (point-min))
          (or (re-search-forward (rx (seq "def" (+ space) (literal label) (* space) "(")) nil t)
              (search-forward label)))
      (bazel-find--find-target-at-point))))


(defun bazel-find--clear-project-dirs ()
  "Clear the cached project directories."
  (interactive)
  (setq bazel-find--project-dirs '()))


(define-derived-mode bazel-find-build-mode bazel-build-mode "Bazel Find"
  "Custom Bazel mode."
  (bazel-find--set-keybindings))

(define-derived-mode bazel-find-starlark-mode bazel-starlark-mode "Starlark Find"
  "Custom Starlark mode."
  (bazel-find--set-keybindings))

(add-to-list 'auto-mode-alist '("\\BUILD.bazel\\'" . bazel-find-build-mode))
(add-to-list 'auto-mode-alist '("\\BUILD\\'" . bazel-find-build-mode))
(add-to-list 'auto-mode-alist '("\\WORKSPACE\\'" . bazel-find-build-mode))
(add-to-list 'auto-mode-alist '("\\.bzl\\'" . bazel-find-starlark-mode))

(provide 'bazel-find-mode)

;;; bazel-find-mode.el ends here
