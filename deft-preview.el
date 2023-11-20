;;; deft-preview.el --- Minor mode to preview files in Deft  -*- lexical-binding: t; -*-

;; Copyright (C) 2023  Shankar Rao

;; Author: Shankar Rao <shankar.rao@gmail.com>
;; URL: https://github.com/shankar2k/deft-preview
;; Version: 0.1
;; Package-Requires: ((emacs "25.1"))
;; Keywords: convenience, file, plain text, notes, preview, deft, Notational Velocity

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
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package is a minor mode which enhances Deft in various ways to make it
;; a more high-fidelity emulation of the Notational Velocity application [1] upon
;; which it is based. In particular, it adds the following features:

;; - Preview the file at point in the Deft buffer. The preview is updated
;;   whenever the line number of the point is changed, or when the Deft filter
;;   is changed.
;;
;; - Highlight the current line in the Deft buffer.

;;;; Installation

;;;;; Manual

;; To start using it, place it somewhere in your Emacs load-path and add it as a
;; company backend with following commands:

;; (require 'deft-preview)
;; (deft-preview-mode +1)

;; If you use use-package, you can configure this as follows:

;; (use-package deft-preview
;;   :load-path (lambda () "<path to deft-preview dir>")
;;   :after (deft)
;;   :ensure nil
;;   :config
;;   (deft-preview-mode +1))

;;;; Credits

;; This package extends the Deft package [2] and also leverages the temporary
;; file previewing capability of Dired Preview [3].
;;
;;  [1] https://notational.net/
;;  [2] https://jblevins.org/projects/deft/
;;  [3] https://protesilaos.com/emacs/dired-preview

;;; License:

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

;;; History:

;; Version 0.1 (2023-11-20):

;; - Initial version with previewing and line highlighting

;;; Code:

;;;; Requirements

(require 'deft)
(require 'hl-line)
(require 'dired-preview)

;;;; Customization

(defgroup deft-preview nil
  "Automatically preview file at point in Deft."
  :group 'deft)

(defcustom deft-preview-highlight-line t
  "If true, highlight the current line in the Deft buffer to show which
file is currently being preview.")

;;;; Constants / Variables

(defvar deft-preview-line 0
  "Current line number in the Deft buffer.")

;;;; Functions

(defun deft-preview-enable ()
  "Enable Deft Preview mode in current buffer."
  (add-hook 'pre-command-hook #'deft-preview-pre-move-hook nil :local)
  (add-hook 'post-command-hook #'deft-preview-post-move-hook nil :local)
  (add-hook 'deft-filter-hook #'deft-preview-filter nil :local)
  (when deft-preview-highlight-line
    (hl-line-mode +1)))

(defun deft-preview-disable ()
  "Disable Deft Preview mode in current buffer."
  (remove-hook 'pre-command-hook #'deft-preview-pre-move-hook :local)
  (remove-hook 'post-command-hook #'deft-preview-post-move-hook :local)
  (remove-hook 'deft-filter-hook #'deft-preview-filter :local)
  (when deft-preview-highlight-line
    (hl-line-mode -1))
  (dired-preview--close-previews))


(defun deft-preview-pre-move-hook ()
  "Save current line number before performing command in Deft buffer.

This function is added to ``pre-command-hook'' when Deft Preview
mode is enabled."
  (setq deft-preview-line (line-number-at-pos)))

(defun deft-preview-post-move-hook ()
  "Preview file at point if post command point is on a new line.

This function is added to ``post-command-hook'' when Deft Preview
mode is enabled."
  (unless (= deft-preview-line (line-number-at-pos))
    ;; (message "Preview because of move, cmd=%S, mline = %S, line#=%S"
    ;;          this-command deft-preview-line (line-number-at-pos))
    (deft-preview-file)))

(defun deft-preview-file ()
  "Preview file at point if possible.

If there is no file at point, close the preview window."
  (add-hook 'window-state-change-hook #'deft-preview--close-outside-deft)
  (if-let ((file (save-excursion
                   (beginning-of-line)
                   (deft-filename-at-point))))
      (dired-preview-display-file file)
    (dired-preview--close-previews)))
 
(defun deft-preview-filter ()
  "Preview file at point if the Deft filter string is non-empty.

This is function is added to ``deft-filter-hook'' when Deft
Preview mode is enabled."
  (if deft-filter-regexp
      (progn
        ;; (message "Preview because of filter = %S" deft-filter-regexp)
        (deft-preview-file))
    (dired-preview--close-previews)))

;;;###autoload
(define-minor-mode deft-preview-mode
  "Buffer-local mode to preview file at point in Deft."
  :init-value nil
  (deft-preview--run-in-deft (if deft-preview-mode
                                 #'deft-preview-enable
                               #'deft-preview-disable)))

;;;;; Support
;;;;;; Private Helper Functions

(defun deft-preview--close-outside-deft ()
  "Call `deft-preview--close-previews' if BUFFER is not in Deft mode."
  (unless (eq major-mode 'deft-mode)
    (dired-preview--close-previews)
    (remove-hook 'window-state-change-hook
                 #'deft-preview--close-outside-deft)))

(defun deft-preview--run-in-deft (func)
  "Run FUNC in Deft buffer.

If Deft is not active, add FUNC to ``deft-mode-hook'' so that it
will be run when Deft is loaded."
  (if (get-buffer deft-buffer)
      (with-current-buffer deft-buffer
        (funcall func))
    (add-hook 'deft-mode-hook func nil :local)))

;;;; Footer

(provide 'deft-preview)
;;; deft-preview.el ends here
