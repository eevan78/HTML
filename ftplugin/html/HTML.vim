vim9script
scriptencoding utf8

if v:version < 802 || v:versionlong < 8024023
  echoerr 'The HTML macros plugin no longer supports Vim versions prior to 8.2.4023'
  sleep 3
  finish
endif

# ---- Author & Copyright: ---------------------------------------------- {{{1
#
# Author:           Christian J. Robinson <heptite(at)gmail(dot)com>
# URL:              https://christianrobinson.name/HTML/
# Last Change:      January 09, 2022
# Original Concept: Doug Renze
#
# The original Copyright goes to Doug Renze, although nearly all of his
# efforts have been modified in this implementation.  My changes and additions
# are Copyrighted by me, on the dates marked in the ChangeLog.
#
# (Doug Renze has authorized me to place the original "code" under the GPL.)
#
# ----------------------------------------------------------------------------
#
# This program is free software; you can  redistribute  it  and/or  modify  it
# under the terms of the GNU General Public License as published by  the  Free
# Software Foundation; either version 3 of the License, or  (at  your  option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but  WITHOUT
# ANY WARRANTY; without  even  the  implied  warranty  of  MERCHANTABILITY  or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General  Public  License  for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place  -  Suite  330,  Boston,  MA  02111-1307,  USA.   Or  you  can  go  to
# https://www.gnu.org/licenses/licenses.html#GPL
#
# ---- Original Author's Notes: ----------------------------------------------
#
# HTML Macros
#        I wrote these HTML macros for my personal use.  They're
#        freely-distributable and freely-modifiable.
#
#        If you do make any major additions or changes, or even just
#        have a suggestion for improvement, feel free to let me
#        know.  I'd appreciate any suggestions.
#
#        Credit must go to Eric Tilton, Carl Steadman and Tyler
#        Jones for their excellent book "Web Weaving" which was
#        my primary source.
#
#        Doug Renze
#
# ---- TODO: ------------------------------------------------------------ {{{1
#
# - Add a lot more character entities (see table in import/HTML.vim)
# - Add more HTML 5 tags?
#   https://www.w3.org/wiki/HTML/New_HTML5_Elements
#   https://www.w3.org/community/webed/wiki/HTML/New_HTML5_Elements
# - Find a way to make "gv"--after executing a visual mapping--re-select the
#   right text.  (Currently my extra code that wraps around the visual
#   mappings can tweak the selected area significantly.)
#   + This should probably exclude the newly created tag text, so things like
#     visual selection ;ta, then gv and ;tr, then gv and ;td work.
#
# ----------------------------------------------------------------------- }}}1

# ---- Initialization: -------------------------------------------------- {{{1

import "../../import/HTML.vim"

# Do this here instead of below, because it's referenced early:
if !exists('g:htmlplugin')
  g:htmlplugin = {}
endif
if !exists('b:htmlplugin')
  b:htmlplugin = {}
endif

runtime! commands/HTML.vim

if !HTML#BoolVar('b:htmlplugin.did_mappings_init')
  # This must be a number, not a boolean, because a -1 special case is used by
  # one of the functions:
  b:htmlplugin.did_mappings_init = 1

  # Configuration variables:  {{{2
  # (These should be set in the user's vimrc or a filetype plugin, rather than
  # changed here.)
  SetIfUnset g:htmlplugin.bgcolor                #FFFFFF
  SetIfUnset g:htmlplugin.textcolor              #000000
  SetIfUnset g:htmlplugin.linkcolor              #0000EE
  SetIfUnset g:htmlplugin.alinkcolor             #FF0000
  SetIfUnset g:htmlplugin.vlinkcolor             #990066
  SetIfUnset g:htmlplugin.tag_case               lowercase
  SetIfUnset g:htmlplugin.map_leader             ;
  SetIfUnset g:htmlplugin.entity_map_leader      &
  SetIfUnset g:htmlplugin.default_charset        UTF-8
  # No way to know sensible defaults here so just make sure the
  # variables are set:
  SetIfUnset g:htmlplugin.authorname             ''
  SetIfUnset g:htmlplugin.authoremail            ''
  # Empty list means the HTML menu is its own toplevel:
  SetIfUnset g:htmlplugin.toplevel_menu          []
  # -1 means let Vim put the menu wherever it wants to by default:
  SetIfUnset g:htmlplugin.toplevel_menu_priority -1
  # END configurable variables

  # Intitialize some necessary variables:  {{{2
  SetIfUnset g:htmlplugin.function_files []

  # Need to inerpolate the value, which the command form of SetIfUnset doesn't
  # do:
  HTML#SetIfUnset('g:htmlplugin.save_clipboard', &clipboard)

  # Always set this, even if it was already set:
  if exists('g:htmlplugin.file')
    unlockvar g:htmlplugin.file
  endif
  g:htmlplugin.file = expand('<sfile>:p')
  lockvar g:htmlplugin.file

  if type(g:htmlplugin.toplevel_menu) != v:t_list
    HTMLERROR g:htmlplugin.toplevel_menu must be a list! Overriding.
    sleep 3
    g:htmlplugin.toplevel_menu = []
  endif

  if !exists('g:htmlplugin.toplevel_menu_escaped')
    g:htmlplugin.toplevel_menu_escaped =
      g:htmlplugin.toplevel_menu->add(HTML.MENU_NAME)->HTML#MenuJoin()
    lockvar g:htmlplugin.toplevel_menu
    lockvar g:htmlplugin.toplevel_menu_escaped
  endif

  silent! setlocal clipboard+=html
  setlocal matchpairs+=<:>

  if g:htmlplugin.entity_map_leader ==# g:htmlplugin.map_leader
    HTMLERROR "g:htmlplugin.entity_map_leader" and "g:htmlplugin.map_leader" have the same value!
    HTMLERROR Resetting both to their defaults.
    sleep 3
    g:htmlplugin.map_leader = ';'
    g:htmlplugin.entity_map_leader = '&'
  endif

  if exists('b:htmlplugin.tag_case')
    # Used by the conrol function to preserve what the user selected when
    # switching off XHTML mode:
    b:htmlplugin.tag_case_save = b:htmlplugin.tag_case
  endif

  # Detect whether to force uppper or lower case:  {{{2
  if &filetype ==? 'xhtml'
      || HTML#BoolVar('g:htmlplugin.do_xhtml_mappings')
      || HTML#BoolVar('b:htmlplugin.do_xhtml_mappings')
    b:htmlplugin.do_xhtml_mappings = true
  else
    b:htmlplugin.do_xhtml_mappings = false

    if HTML#BoolVar('g:htmlplugin.tag_case_autodetect')
        && (line('$') != 1 || getline(1) != '')

      var found_upper = search('\C<\(\s*/\)\?\s*\u\+\_[^<>]*>', 'wn')
      var found_lower = search('\C<\(\s*/\)\?\s*\l\+\_[^<>]*>', 'wn')

      if found_upper != 0 && found_lower == 0
        b:htmlplugin.tag_case = 'uppercase'
      elseif found_upper == 0 && found_lower != 0
        b:htmlplugin.tag_case = 'lowercase'
      else
        # Found a combination of upper and lower case, so just use the user
        # preference:
        b:htmlplugin.tag_case = g:htmlplugin.tag_case
      endif
    endif
  endif

  if HTML#BoolVar('b:htmlplugin.do_xhtml_mappings')
    b:htmlplugin.tag_case = 'lowercase'
  endif

  # Need to inerpolate the value, which the command form of SetIfUnset doesn't
  # do:
  HTML#SetIfUnset('b:htmlplugin.tag_case', g:htmlplugin.tag_case)

  # Template Creation: {{{2

  if HTML#BoolVar('b:htmlplugin.do_xhtml_mappings')
    b:htmlplugin.internal_template = HTML.INTERNAL_TEMPLATE->extendnew([
        '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"',
        ' "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">',
        '<html xmlns="http://www.w3.org/1999/xhtml">'
      ], 0)

    b:htmlplugin.internal_template =
      b:htmlplugin.internal_template->HTML#ConvertCase()
  else
    b:htmlplugin.internal_template = HTML.INTERNAL_TEMPLATE->extendnew([
        '<!DOCTYPE html>',
        '<[{HTML}]>'
      ], 0)

    b:htmlplugin.internal_template =
      b:htmlplugin.internal_template->HTML#ConvertCase()

    b:htmlplugin.internal_template =
      b:htmlplugin.internal_template->mapnew(
          (_, line) => {
            return line->substitute(' />', '>', 'g')
          }
        )
  endif

  # }}}2

endif # !exists('b:htmlplugin.did_mappings_init')

# ----------------------------------------------------------------------------

# ---- Miscellaneous Mappings: ------------------------------------------ {{{1

b:htmlplugin.doing_internal_mappings = true

if !HTML#BoolVar('b:htmlplugin.did_mappings')
b:htmlplugin.did_mappings = true

b:htmlplugin.clear_mappings = []

# Make it easy to use a ; (or whatever the map leader is) as normal:
HTML#Map('inoremap', '<lead>' .. g:htmlplugin.map_leader, g:htmlplugin.map_leader)
HTML#Map('vnoremap', '<lead>' .. g:htmlplugin.map_leader, g:htmlplugin.map_leader, {'extra': false})
HTML#Map('nnoremap', '<lead>' .. g:htmlplugin.map_leader, g:htmlplugin.map_leader)
# Make it easy to insert a & (or whatever the entity leader is):
HTML#Map('inoremap', '<lead>' .. g:htmlplugin.entity_map_leader, g:htmlplugin.entity_map_leader)

if !HTML#BoolVar('g:htmlplugin.no_tab_mapping')
  # Allow hard tabs to be used:
  HTML#Map('inoremap', '<lead><tab>', '<tab>')
  HTML#Map('nnoremap', '<lead><tab>', '<tab>')
  HTML#Map('vnoremap', '<lead><tab>', '<tab>', {'extra': false})
  # And shift-tabs too:
  HTML#Map('inoremap', '<lead><s-tab>', '<s-tab>')
  HTML#Map('nnoremap', '<lead><s-tab>', '<s-tab>')
  HTML#Map('vnoremap', '<lead><s-tab>', '<s-tab>', {'extra': false})

  # Tab takes us to a (hopefully) reasonable next insert point:
  HTML#Map('inoremap', '<tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('i')<CR>")
  HTML#Map('nnoremap', '<tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('n')<CR>")
  HTML#Map('vnoremap', '<tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('n')<CR>", {'extra': false})
  # ...And shift-tab goes backwards:
  HTML#Map('inoremap', '<s-tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('i', 'b')<CR>")
  HTML#Map('nnoremap', '<s-tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('n', 'b')<CR>")
  HTML#Map('vnoremap', '<s-tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('n', 'b')<CR>", {'extra': false})
else
  HTML#Map('inoremap', '<lead><tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('i')<CR>")
  HTML#Map('nnoremap', '<lead><tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('n')<CR>")
  HTML#Map('vnoremap', '<lead><tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('n')<CR>", {'extra': false})

  HTML#Map('inoremap', '<lead><s-tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('i', 'b')<CR>")
  HTML#Map('nnoremap', '<lead><s-tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('n', 'b')<CR>")
  HTML#Map('vnoremap', '<lead><s-tab>', "<Cmd>vim9cmd HTML#NextInsertPoint('n', 'b')<CR>", {'extra': false})
endif

# ----------------------------------------------------------------------------

# ---- General Markup Tag Mappings: ------------------------------------- {{{1

# Cannot conditionally set mappings in the tags.json file, so do this set of
# mappings here instead:

#       SGML Doctype Command
if HTML#BoolVar('b:htmlplugin.do_xhtml_mappings')
  # Transitional XHTML (Looser):
  HTML#Map('nnoremap', '<lead>4', "<Cmd>vim9cmd append(0, '<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\"') \\\| vim9cmd append(1, ' \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">')<CR>")
  # Strict XHTML:
  HTML#Map('nnoremap', '<lead>s4', "<Cmd>vim9cmd append(0, '<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"') \\\| vim9cmd append(1, ' \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">')<CR>")
else
  # Transitional HTML (Looser):
  HTML#Map('nnoremap', '<lead>4', "<Cmd>vim9cmd append(0, '<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\"') \\\| vim9cmd append(1, ' \"http://www.w3.org/TR/html4/loose.dtd\">')<CR>")
  # Strict HTML:
  HTML#Map('nnoremap', '<lead>s4', "<Cmd>vim9cmd append(0, '<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\"') \\\| vim9cmd append(1, ' \"http://www.w3.org/TR/html4/strict.dtd\">')<CR>")
endif
HTML#Map('imap', '<lead>4', '<C-O>' .. g:htmlplugin.map_leader .. '4')
HTML#Map('imap', '<lead>s4', '<C-O>' .. g:htmlplugin.map_leader .. 's4')

#       HTML5 Doctype Command           HTML 5
HTML#Map('nnoremap', '<lead>5', "<Cmd>vim9cmd append(0, '<!DOCTYPE html>')<CR>")
HTML#Map('imap', '<lead>5', '<C-O>' .. g:htmlplugin.map_leader .. '5')


#       HTML
if HTML#BoolVar('b:htmlplugin.do_xhtml_mappings')
  HTML#Map('inoremap', '<lead>ht', '<html xmlns="http://www.w3.org/1999/xhtml"><CR></html><ESC>O')
  # Visual mapping:
  HTML#Map('vnoremap', '<lead>ht', '<ESC>`>a<CR></html><C-O>`<<html xmlns="http://www.w3.org/1999/xhtml"><CR><ESC>', {'reindent': 1})
else
  HTML#Map('inoremap', '<lead>ht', '<[{HTML}]><CR></[{HTML}]><ESC>O')
  # Visual mapping:
  HTML#Map('vnoremap', '<lead>ht', '<ESC>`>a<CR></[{HTML}]><C-O>`<<[{HTML}]><CR><ESC>', {'reindent': 1})
endif
# Motion mapping:
HTML#Mapo('<lead>ht')

if HTML#BoolVar('g:htmlplugin.did_menus')
  # Basically, we get here by having the user open a new HTML file after
  # already loading one, so the menus don't need to be loaded again, just the
  # mappings for this buffer:
  HTML#ReadEntities(false, true)
  HTML#ReadTags(false, true)
endif

# ----------------------------------------------------------------------------

# ---- Character Entities Mappings: ------------------------------------- {{{1

# Convert the character under the cursor or the highlighted string to its name
# entity or otherwise decimal HTML entities:
# (Note that this can be very slow due to syntax highlighting. Maybe find a
# different way to do it?)
HTML#Map('vnoremap', '<lead>&', "s<C-R>=HTML#TranscodeString(@\")->HTML#SI()<CR><Esc>", {'extra': false})
HTML#Mapo('<lead>&')

# Convert the character under the cursor or the highlighted string to hex
# HTML entities:
HTML#Map('vnoremap', '<lead>*', "s<C-R>=HTML#TranscodeString(@\", 'x')->HTML#SI()<CR><Esc>", {'extra': false})
HTML#Mapo('<lead>*')

# Convert the character under the cursor or the highlighted string to a %XX
# string:
HTML#Map('vnoremap', '<lead>%', "s<C-R>=HTML#TranscodeString(@\", '%')->HTML#SI()<CR><Esc>", {'extra': false})
HTML#Mapo('<lead>%')

# Decode a &...;, &#...;, or %XX encoded string:
HTML#Map('vnoremap', '<lead>^', "s<C-R>=HTML#TranscodeString(@\", 'd')->HTML#SI()<CR><Esc>", {'extra': false})
HTML#Mapo('<lead>^')

# The actual entity mappings are now defined in a json file to reduce
# work on defining both the entities and entity menu items, see below.

# ----------------------------------------------------------------------------

# ---- Browser Remote Controls: ----------------------------------------- {{{1

var BrowserLauncherExists: bool
# try/catch because the function won't autoload if it's not installed:
try
  BrowserLauncherExists = BrowserLauncher#Exists() != []
catch /^Vim\%((\a\+)\)\=:E117:.\+BrowserLauncher#Exists/
  BrowserLauncherExists = false
endtry

if BrowserLauncherExists
  if BrowserLauncher#Exists('default')
    # Run the default browser:
    HTML#Map(
      'nnoremap',
      '<lead>db',
      ":vim9cmd BrowserLauncher#Launch('default')<CR>"
    )
  endif

  if BrowserLauncher#Exists('brave')
    # Chrome: View current file, starting Chrome if it's not running:
    HTML#Map(
      'nnoremap',
      '<lead>bv',
      ":vim9cmd BrowserLauncher#Launch('brave', 0)<CR>"
    )
    # Chrome: Open a new window, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>nbv',
      ":vim9cmd BrowserLauncher#Launch('brave', 1)<CR>"
    )
    # Chrome: Open a new tab, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>tbv',
      ":vim9cmd BrowserLauncher#Launch('brave', 2)<CR>"
    )
  endif

  if BrowserLauncher#Exists('firefox')
    # Firefox: View current file, starting Firefox if it's not running:
    HTML#Map(
      'nnoremap',
      '<lead>ff',
      ":vim9cmd BrowserLauncher#Launch('firefox', 0)<CR>"
    )
    # Firefox: Open a new window, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>nff',
      ":vim9cmd BrowserLauncher#Launch('firefox', 1)<CR>"
    )
    # Firefox: Open a new tab, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>tff',
      ":vim9cmd BrowserLauncher#Launch('firefox', 2)<CR>"
    )
  endif

  if BrowserLauncher#Exists('chrome')
    # Chrome: View current file, starting Chrome if it's not running:
    HTML#Map(
      'nnoremap',
      '<lead>gc',
      ":vim9cmd BrowserLauncher#Launch('chrome', 0)<CR>"
    )
    # Chrome: Open a new window, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>ngc',
      ":vim9cmd BrowserLauncher#Launch('chrome', 1)<CR>"
    )
    # Chrome: Open a new tab, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>tgc',
      ":vim9cmd BrowserLauncher#Launch('chrome', 2)<CR>"
    )
  endif

  if BrowserLauncher#Exists('edge')
    # Edge: View current file, starting Microsoft Edge if it's not running:
    HTML#Map(
      'nnoremap',
      '<lead>ed',
      ":vim9cmd BrowserLauncher#Launch('edge', 0)<CR>"
    )
    # Edge: Open a new window, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>ned',
      ":vim9cmd BrowserLauncher#Launch('edge', 1)<CR>"
    )
    # Edge: Open a new tab, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>ted',
      ":vim9cmd BrowserLauncher#Launch('edge', 2)<CR>"
    )
  endif

  if BrowserLauncher#Exists('opera')
    # Opera: View current file, starting Opera if it's not running:
    HTML#Map(
      'nnoremap',
      '<lead>oa',
      ":vim9cmd BrowserLauncher#Launch('opera', 0)<CR>"
    )
    # Opera: Open a new window, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>noa',
      ":vim9cmd BrowserLauncher#Launch('opera', 1)<CR>"
    )
    # Opera: Open a new tab, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>toa',
      ":vim9cmd BrowserLauncher#Launch('opera', 2)<CR>"
    )
  endif

  if BrowserLauncher#Exists('safari')
    # Safari: View current file, starting Safari if it's not running:
    HTML#Map(
      'nnoremap',
      '<lead>sf',
      ":vim9cmd BrowserLauncher#Launch('safari', 0)<CR>"
    )
    # Safari: Open a new window, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>nsf',
      ":vim9cmd BrowserLauncher#Launch('safari', 1)<CR>"
      )
    # Safari: Open a new tab, and view the current file:
    HTML#Map(
      'nnoremap',
      '<lead>tsf',
      ":vim9cmd BrowserLauncher#Launch('safari', 2)<CR>"
    )
  endif

  if BrowserLauncher#Exists('lynx')
    # Lynx:  (This may happen anyway if there's no GUI available.)
    HTML#Map(
      'nnoremap',
      '<lead>ly',
      ":vim9cmd BrowserLauncher#Launch('lynx', 0)<CR>"
    )
    # Lynx in an xterm:  (This always happens in the Vim GUI.)
    HTML#Map(
      'nnoremap',
      '<lead>nly',
      ":vim9cmd BrowserLauncher#Launch('lynx', 1)<CR>"
    )
    # Lynx in a new Vim window, using :terminal:
    HTML#Map(
      'nnoremap',
      '<lead>tly',
      ":vim9cmd BrowserLauncher#Launch('lynx', 2)<CR>"
    )
  endif

  if BrowserLauncher#Exists('w3m')
    # w3m:  (This may happen anyway if there's no GUI available.)
    HTML#Map(
      'nnoremap',
      '<lead>w3',
      ":vim9cmd BrowserLauncher#Launch('w3m', 0)<CR>"
    )
    # w3m in an xterm:  (This always happens in the Vim GUI.)
    HTML#Map(
      'nnoremap',
      '<lead>nw3',
      ":vim9cmd BrowserLauncher#Launch('w3m', 1)<CR>"
    )
    # w3m in a new Vim window, using :terminal:
    HTML#Map(
      'nnoremap',
      '<lead>tw3',
      ":vim9cmd BrowserLauncher#Launch('w3m', 2)<CR>"
    )
  endif

  if BrowserLauncher#Exists('links')
    # Links:  (This may happen anyway if there's no GUI available.)
    HTML#Map(
      'nnoremap',
      '<lead>ln',
      ":vim9cmd BrowserLauncher#Launch('links', 0)<CR>"
    )
    # Lynx in an xterm:  (This always happens in the Vim GUI.)
    HTML#Map(
      'nnoremap',
      '<lead>nln',
      ":vim9cmd BrowserLauncher#Launch('links', 1)<CR>"
    )
    # Lynx in a new Vim window, using :terminal:
    HTML#Map(
      'nnoremap',
      '<lead>tln',
      ":vim9cmd BrowserLauncher#Launch('links', 2)<CR>"
    )
  endif
endif

# ----------------------------------------------------------------------------

endif # ! exists('b:htmlplugin.did_mappings')

# ---- ToolBar Buttons: ------------------------------------------------- {{{1

if ! has('gui_running') && !HTML#BoolVar('g:htmlplugin.force_menu')
  def CreateBufEnterOnce(): void
    augroup HTMLpluginonce
      au!
      autocmd BufEnter * {
          if HTML#BoolVar('b:htmlplugin.did_mappings_init')
            execute 'source ' .. g:htmlplugin.file
            execute 'autocmd! HTMLpluginonce'
          endif
        }
    augroup END
  enddef

  augroup HTMLplugin
    au!
    autocmd GUIEnter * ++once {
        if HTML#BoolVar('b:htmlplugin.did_mappings_init')
          execute 'source ' .. g:htmlplugin.file
        else
          eval CreateBufEnterOnce()
        endif
      }
  augroup END

  # Since the user didn't start the GUI and didn't force menus, bring in the
  # entities and tags mappings, without the menus:
  HTML#ReadEntities(false, true)
  HTML#ReadTags(false, true)
elseif HTML#BoolVar('g:htmlplugin.did_menus')
  HTML#MenuControl()
elseif !HTML#BoolVar('g:htmlplugin.no_menu')

# Solve a race condition:
if ! exists('g:did_install_default_menus')
  source $VIMRUNTIME/menu.vim
endif

if !HTML#BoolVar('g:htmlplugin.no_toolbar') && has('toolbar')

  if findfile('bitmaps/Browser.bmp', &runtimepath) == ''
    var message = "Warning:\nYou need to install the Toolbar Bitmaps for the "
      .. g:htmlplugin.file->fnamemodify(':t') .. " plugin.\n"
      .. 'See: ' .. (HTML.HOMEPAGE) .. "#files\n"
      .. 'Or see ":help g:htmlplugin.no_toolbar".'
    var ret = message->confirm("&Dismiss\nView &Help\nGet &Bitmaps", 1, 'Warning')

    if ret == 2
      help g:htmlplugin.no_toolbar
      # Go to the previous window or everything gets messy:
      wincmd p
    elseif ret == 3
      BrowserLauncher#Launch('default', 0, HTML.HOMEPAGE .. '#files')
    endif
  endif

  # In the context of running ":gui" after starting the non-GUI, unfortunately
  # there's no way to make this work if the user has 'guioptions' set in their
  # gvimrc, and it removes the 'T'.
  if has('gui_running')
    set guioptions+=T
  else
    augroup HTMLplugin
      autocmd GUIEnter * set guioptions+=T
    augroup END
  endif

  # Save some menu stuff from the global menu.vim so we can reuse them
  # later--this makes sure updates from menu.vim make it into this codebase:
  var save_toolbar: dict<string>
  save_toolbar['open']      = menu_info('ToolBar.Open')['rhs']->escape('|')
  save_toolbar['save']      = menu_info('ToolBar.Save')['rhs']->escape('|')
  save_toolbar['saveall']   = menu_info('ToolBar.SaveAll')['rhs']->escape('|')
  save_toolbar['replace']   = menu_info('ToolBar.Replace')['rhs']->escape('|')
  save_toolbar['replace_v'] = menu_info('ToolBar.Replace', 'v')['rhs']->escape('|')
  save_toolbar['cut_v']     = menu_info('ToolBar.Cut', 'v')['rhs']->escape('|')
  save_toolbar['copy_v']    = menu_info('ToolBar.Copy', 'v')['rhs']->escape('|')
  save_toolbar['paste_n']   = menu_info('ToolBar.Paste', 'n')['rhs']->escape('|')
  save_toolbar['paste_c']   = menu_info('ToolBar.Paste', 'c')['rhs']->escape('|')
  save_toolbar['paste_i']   = menu_info('ToolBar.Paste', 'i')['rhs']->escape('|')
  save_toolbar['paste_v']   = menu_info('ToolBar.Paste', 'v')['rhs']->escape('|')

  silent! unmenu ToolBar
  silent! unmenu! ToolBar

  # For some reason, the tmenu commands must come before the other menu
  # commands for that menu item, or GTK versions of gVim don't show the
  # icons properly.

  HTML#Menu('tmenu',     '1.10',  ['ToolBar', 'Open'],      'Open File')
  HTML#Menu('anoremenu', '1.10',  ['ToolBar', 'Open'],      save_toolbar['open'])
  HTML#Menu('tmenu',     '1.20',  ['ToolBar', 'Save'],      'Save Current File')
  HTML#Menu('anoremenu', '1.20',  ['ToolBar', 'Save'],      save_toolbar['save'])
  HTML#Menu('tmenu',     '1.30',  ['ToolBar', 'SaveAll'],   'Save All Files')
  HTML#Menu('anoremenu', '1.30',  ['ToolBar', 'SaveAll'],   save_toolbar['saveall'])

  HTML#Menu('menu',      '1.50',  ['ToolBar', '-sep1-'],    '<Nop>')

  HTML#Menu('tmenu',     '1.60',  ['ToolBar', 'Template'],  'Insert Template')
  HTML#LeadMenu('amenu', '1.60',  ['ToolBar', 'Template'],  'html')

  HTML#Menu('menu',      '1.65',  ['ToolBar', '-sep2-'],    '<Nop>')

  HTML#Menu('tmenu',     '1.70',  ['ToolBar', 'Paragraph'], 'Create Paragraph')
  HTML#LeadMenu('imenu', '1.70',  ['ToolBar', 'Paragraph'], 'pp')
  HTML#LeadMenu('vmenu', '-',     ['ToolBar', 'Paragraph'], 'pp')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Paragraph'], 'pp', 'i')
  HTML#Menu('tmenu',     '1.80',  ['ToolBar', 'Break'],     'Line Break')
  HTML#LeadMenu('imenu', '1.80',  ['ToolBar', 'Break'],     'br')
  HTML#LeadMenu('vmenu', '-',     ['ToolBar', 'Break'],     'br')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Break'],     'br', 'i')

  HTML#Menu('menu',      '1.85',  ['ToolBar', '-sep3-'],    '<Nop>')

  HTML#Menu('tmenu',     '1.90',  ['ToolBar', 'Link'],      'Create Hyperlink')
  HTML#LeadMenu('imenu', '1.90',  ['ToolBar', 'Link'],      'ah')
  HTML#LeadMenu('vmenu', '-',     ['ToolBar', 'Link'],      'ah')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Link'],      'ah', 'i')
  HTML#Menu('tmenu',     '1.100', ['ToolBar', 'Image'],     'Insert Image')
  HTML#LeadMenu('imenu', '1.100', ['ToolBar', 'Image'],     'im')
  HTML#LeadMenu('vmenu', '-',     ['ToolBar', 'Image'],     'im')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Image'],     'im', 'i')

  HTML#Menu('menu',      '1.105', ['ToolBar', '-sep4-'],    '<Nop>')

  HTML#Menu('tmenu',     '1.110', ['ToolBar', 'Hline'],     'Create Horizontal Rule')
  HTML#LeadMenu('imenu', '1.110', ['ToolBar', 'Hline'],     'hr')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Hline'],     'hr', 'i')

  HTML#Menu('menu',      '1.115', ['ToolBar', '-sep5-'],    '<Nop>')

  HTML#Menu('tmenu',     '1.120', ['ToolBar', 'Table'],     'Create Table')
  HTML#LeadMenu('imenu', '1.120', ['ToolBar', 'Table'],     'tA <ESC>')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Table'],     'tA')

  HTML#Menu('menu',      '1.125', ['ToolBar', '-sep6-'],    '<Nop>')

  HTML#Menu('tmenu',     '1.130', ['ToolBar', 'Blist'],     'Create Bullet List')
  HTML#Menu('imenu',     '1.130', ['ToolBar', 'Blist'],
    g:htmlplugin.map_leader .. 'ul' .. g:htmlplugin.map_leader .. 'li')
  HTML#Menu('vmenu',     '-',     ['ToolBar', 'Blist'], 
    g:htmlplugin.map_leader .. 'uli' .. g:htmlplugin.map_leader .. 'li<ESC>')
  HTML#Menu('nmenu',     '-',     ['ToolBar', 'Blist'], 
    'i' .. g:htmlplugin.map_leader .. 'ul' .. g:htmlplugin.map_leader .. 'li')
  HTML#Menu('tmenu',     '1.140', ['ToolBar', 'Nlist'],     'Create Numbered List')
  HTML#Menu('imenu',     '1.140', ['ToolBar', 'Nlist'], 
    g:htmlplugin.map_leader .. 'ol' .. g:htmlplugin.map_leader .. 'li')
  HTML#Menu('vmenu',     '-',     ['ToolBar', 'Nlist'], 
    g:htmlplugin.map_leader .. 'oli' .. g:htmlplugin.map_leader .. 'li<ESC>')
  HTML#Menu('nmenu',     '-',     ['ToolBar', 'Nlist'], 
    'i' .. g:htmlplugin.map_leader .. 'ol' .. g:htmlplugin.map_leader .. 'li')
  HTML#Menu('tmenu',     '1.150', ['ToolBar', 'Litem'],     'Add List Item')
  HTML#LeadMenu('imenu', '1.150', ['ToolBar', 'Litem'],     'li')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Litem'],     'li', 'i')

  HTML#Menu('menu',      '1.155', ['ToolBar', '-sep7-'],    '<Nop>')

  HTML#Menu('tmenu',     '1.160', ['ToolBar', 'Bold'],      'Bold')
  HTML#LeadMenu('imenu', '1.160', ['ToolBar', 'Bold'],      'bo')
  HTML#LeadMenu('vmenu', '-',     ['ToolBar', 'Bold'],      'bo')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Bold'],      'bo', 'i')
  HTML#Menu('tmenu',     '1.170', ['ToolBar', 'Italic'],    'Italic')
  HTML#LeadMenu('imenu', '1.170', ['ToolBar', 'Italic'],    'it')
  HTML#LeadMenu('vmenu', '-',     ['ToolBar', 'Italic'],    'it')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Italic'],    'it', 'i')
  HTML#Menu('tmenu',     '1.180', ['ToolBar', 'Underline'], 'Underline')
  HTML#LeadMenu('imenu', '1.180', ['ToolBar', 'Underline'], 'un')
  HTML#LeadMenu('vmenu', '-',     ['ToolBar', 'Underline'], 'un')
  HTML#LeadMenu('nmenu', '-',     ['ToolBar', 'Underline'], 'un', 'i')

  HTML#Menu('menu',      '1.185', ['ToolBar', '-sep8-'],    '<Nop>')

  HTML#Menu('tmenu',     '1.190', ['ToolBar', 'Undo'],      'Undo')
  HTML#Menu('anoremenu', '1.190', ['ToolBar', 'Undo'],      'u')
  HTML#Menu('tmenu',     '1.200', ['ToolBar', 'Redo'],      'Redo')
  HTML#Menu('anoremenu', '1.200', ['ToolBar', 'Redo'],      '<C-R>')

  HTML#Menu('menu',      '1.205', ['ToolBar', '-sep9-'],    '<Nop>')

  HTML#Menu('tmenu',     '1.210', ['ToolBar', 'Cut'],       'Cut to Clipboard')
  HTML#Menu('vnoremenu', '1.210', ['ToolBar', 'Cut'],       save_toolbar['cut_v'])
  HTML#Menu('tmenu',     '1.220', ['ToolBar', 'Copy'],      'Copy to Clipboard')
  HTML#Menu('vnoremenu', '1.220', ['ToolBar', 'Copy'],      save_toolbar['copy_v'])
  HTML#Menu('tmenu',     '1.230', ['ToolBar', 'Paste'],     'Paste from Clipboard')
  HTML#Menu('nnoremenu', '1.230', ['ToolBar', 'Paste'],     save_toolbar['paste_n'])
  HTML#Menu('cnoremenu', '-',     ['ToolBar', 'Paste'],     save_toolbar['paste_c'])
  HTML#Menu('inoremenu', '-',     ['ToolBar', 'Paste'],     save_toolbar['paste_i'])
  HTML#Menu('vnoremenu', '-',     ['ToolBar', 'Paste'],     save_toolbar['paste_v'])

  HTML#Menu('menu',      '1.235', ['ToolBar', '-sep10-'],   '<Nop>')

  if !has('gui_athena')
    HTML#Menu('tmenu',       '1.240', ['ToolBar', 'Replace'],  'Find / Replace')
    HTML#Menu('anoremenu',   '1.240', ['ToolBar', 'Replace'],  save_toolbar['replace'])
    vunmenu ToolBar.Replace
    HTML#Menu('vnoremenu',   '-',     ['ToolBar', 'Replace'],  save_toolbar['replace_v'])
    HTML#Menu('tmenu',       '1.250', ['ToolBar', 'FindNext'], 'Find Next')
    HTML#Menu('anoremenu',   '1.250', ['ToolBar', 'FindNext'], 'n')
    HTML#Menu('tmenu',       '1.260', ['ToolBar', 'FindPrev'], 'Find Previous')
    HTML#Menu('anoremenu',   '1.260', ['ToolBar', 'FindPrev'], 'N')
  endif

  HTML#Menu('menu', '1.500', ['ToolBar', '-sep50-'], '<Nop>')

  if maparg(g:htmlplugin.map_leader .. 'db', 'n') != ''
    HTML#Menu('tmenu', '1.510', ['ToolBar', 'Browser'],
      'Launch the Default Browser on the Current File')
    HTML#LeadMenu('amenu', '1.510', ['ToolBar', 'Browser'], 'db')
  endif

  if maparg(g:htmlplugin.map_leader .. 'bv', 'n') != ''
    HTML#Menu('tmenu', '1.530', ['ToolBar', 'Brave'],
      'Launch Brave on the Current File')
    HTML#LeadMenu('amenu', '1.530', ['ToolBar', 'Brave'], 'bv')
  endif

  if maparg(g:htmlplugin.map_leader .. 'ff', 'n') != ''
    HTML#Menu('tmenu', '1.520', ['ToolBar', 'Firefox'],
      'Launch Firefox on the Current File')
    HTML#LeadMenu('amenu', '1.520', ['ToolBar', 'Firefox'], 'ff')
  endif

  if maparg(g:htmlplugin.map_leader .. 'gc', 'n') != ''
    HTML#Menu('tmenu', '1.530', ['ToolBar', 'Chrome'],
      'Launch Chrome on the Current File')
    HTML#LeadMenu('amenu', '1.530', ['ToolBar', 'Chrome'], 'gc')
  endif

  if maparg(g:htmlplugin.map_leader .. 'ed', 'n') != ''
    HTML#Menu('tmenu', '1.540', ['ToolBar', 'Edge'],
      'Launch Edge on the Current File')
    HTML#LeadMenu('amenu', '1.540', ['ToolBar', 'Edge'], 'ed')
  endif

  if maparg(g:htmlplugin.map_leader .. 'oa', 'n') != ''
    HTML#Menu('tmenu', '1.550', ['ToolBar', 'Opera'],
      'Launch Opera on the Current File')
    HTML#LeadMenu('amenu', '1.550', ['ToolBar', 'Opera'], 'oa')
  endif

  if maparg(g:htmlplugin.map_leader .. 'sf', 'n') != ''
    HTML#Menu('tmenu', '1.560', ['ToolBar', 'Safari'],
      'Launch Safari on the Current File')
    HTML#LeadMenu('amenu', '1.560', ['ToolBar', 'Safari'], 'sf')
  endif

  if maparg(g:htmlplugin.map_leader .. 'w3', 'n') != ''
    HTML#Menu('tmenu', '1.570', ['ToolBar', 'w3m'],
      'Launch w3m on the Current File')
    HTML#LeadMenu('amenu', '1.570', ['ToolBar', 'w3m'], 'w3')
  endif

  if maparg(g:htmlplugin.map_leader .. 'ly', 'n') != ''
    HTML#Menu('tmenu', '1.580', ['ToolBar', 'Lynx'],
      'Launch Lynx on the Current File')
    HTML#LeadMenu('amenu', '1.580', ['ToolBar', 'Lynx'], 'ly')
  endif

  if maparg(g:htmlplugin.map_leader .. 'ln', 'n') != ''
    HTML#Menu('tmenu', '1.580', ['ToolBar', 'Links'],
      'Launch Links on the Current File')
    HTML#LeadMenu('amenu', '1.580', ['ToolBar', 'Links'], 'ln')
  endif

  HTML#Menu('menu',      '1.997', ['ToolBar', '-sep99-'], '<Nop>')
  HTML#Menu('tmenu',     '1.998', ['ToolBar', 'HTMLHelp'], 'HTML Plugin Help')
  HTML#Menu('anoremenu', '1.998', ['ToolBar', 'HTMLHelp'], ':help HTML.txt<CR>')

  HTML#Menu('tmenu',     '1.999', ['ToolBar', 'Help'], 'Help')
  HTML#Menu('anoremenu', '1.999', ['ToolBar', 'Help'], ':help<CR>')

  g:htmlplugin.did_toolbar = true
endif  # !HTML#BoolVar('g:htmlplugin.no_toolbar') && has('toolbar')
# ----------------------------------------------------------------------------

# ---- Menu Items: ------------------------------------------------------ {{{1

# Add to the PopUp menu:   {{{2
HTML#Menu('nnoremenu', '1.91', ['PopUp', 'Select Ta&g'],        'vat')
HTML#Menu('onoremenu', '-',    ['PopUp', 'Select Ta&g'],        'at')
HTML#Menu('vnoremenu', '-',    ['PopUp', 'Select Ta&g'],        '<C-c>vat')
HTML#Menu('inoremenu', '-',    ['PopUp', 'Select Ta&g'],        '<C-O>vat')
HTML#Menu('cnoremenu', '-',    ['PopUp', 'Select Ta&g'],        '<C-c>vat')

HTML#Menu('nnoremenu', '1.92', ['PopUp', 'Select &Inner Ta&g'], 'vit')
HTML#Menu('onoremenu', '-',    ['PopUp', 'Select &Inner Ta&g'], 'it')
HTML#Menu('vnoremenu', '-',    ['PopUp', 'Select &Inner Ta&g'], '<C-c>vit')
HTML#Menu('inoremenu', '-',    ['PopUp', 'Select &Inner Ta&g'], '<C-O>vit')
HTML#Menu('cnoremenu', '-',    ['PopUp', 'Select &Inner Ta&g'], '<C-c>vit')
# }}}2

augroup HTMLmenu
au!
  autocmd BufEnter,WinEnter * {
      HTML#MenuControl()
      HTML#ToggleClipboard()
    }
augroup END

# Very first non-ToolBar, non-PopUp menu gets "auto" for its priority to place
# the HTML menu according to user configuration:
HTML#Menu('amenu', 'auto', ['Co&ntrol', '&Disable Mappings<tab>:HTML disable'],
  ':HTMLmappings disable<CR>')
HTML#Menu('amenu', '-',    ['Co&ntrol', '&Enable Mappings<tab>:HTML enable'],
  ':HTMLmappings enable<CR>')
HTML#Menu('menu',  '-',    ['Control',  '-sep1-'], '<Nop>')
HTML#Menu('amenu', '-',    ['Co&ntrol', 'Switch to &HTML mode<tab>:HTML html'],
  ':HTMLmappings html<CR>')
HTML#Menu('amenu', '-',    ['Co&ntrol', 'Switch to &XHTML mode<tab>:HTML xhtml'],
  ':HTMLmappings xhtml<CR>')
HTML#Menu('menu',  '-',    ['Control',  '-sep2-'], '<Nop>')
HTML#Menu('amenu', '-',    ['Co&ntrol', 'Switch to lowercase<tab>:HTML lowercase'],
  ':HTMLmappings lowercase<CR>')
HTML#Menu('amenu', '-',    ['Co&ntrol', 'Switch to uppercase<tab>:HTML uppercase'],
  ':HTMLmappings uppercase<CR>')
HTML#Menu('menu',  '-',    ['Control',  '-sep3-'], '<Nop>')
HTML#Menu('amenu', '-',    ['Co&ntrol', '&Reload Mappings<tab>:HTML reload'],
  ':HTMLmappings reload<CR>')

HTML#Menu('menu',  '.9999', ['-sep999-'], '<Nop>')

HTML#Menu('amenu', '.9999', ['Help', 'HTML Plugin Help<TAB>:help HTML.txt'],
  ':help HTML.txt<CR>')
HTML#Menu('amenu', '.9999', ['Help', 'About the HTML Plugin<TAB>:HTMLAbout'],
  ':HTMLAbout<CR>')

execute 'amenu disable ' .. g:htmlplugin.toplevel_menu_escaped
  .. '.Control.Enable\ Mappings'
if HTML#BoolVar('b:htmlplugin.do_xhtml_mappings')
  execute 'amenu disable ' .. g:htmlplugin.toplevel_menu_escaped
    .. '.Control.Switch\ to\ XHTML\ mode'
  execute 'amenu disable ' .. g:htmlplugin.toplevel_menu_escaped
    .. '.Control.Switch\ to\ uppercase'
  execute 'amenu disable ' .. g:htmlplugin.toplevel_menu_escaped
    .. '.Control.Switch\ to\ lowercase'
else
  execute 'amenu disable ' .. g:htmlplugin.toplevel_menu_escaped
    .. '.Control.Switch\ to\ HTML\ mode'
  if b:htmlplugin.tag_case =~? '^u\(pper\(case\)\?\)\?'
    execute 'amenu disable ' .. g:htmlplugin.toplevel_menu_escaped
      .. '.Control.Switch\ to\ uppercase'
  else
    execute 'amenu disable ' .. g:htmlplugin.toplevel_menu_escaped
      .. '.Control.Switch\ to\ lowercase'
  endif
endif

if maparg(g:htmlplugin.map_leader .. 'db', 'n') != ''
  HTML#LeadMenu('amenu', '-', ['&Preview', '&Default Browser'], 'db')
endif
if maparg(g:htmlplugin.map_leader .. 'bv', 'n') != ''
  HTML#Menu('menu', '-', ['Preview', '-sep1-'], '<nop>')
  HTML#LeadMenu('amenu', '-', ['&Preview', '&Brave'], 'bv')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Brave (New Window)'], 'nbv')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Brave (New Tab)'], 'tbv')
endif
if maparg(g:htmlplugin.map_leader .. 'ff', 'n') != ''
  HTML#Menu('menu', '-', ['Preview', '-sep2-'], '<nop>')
  HTML#LeadMenu('amenu', '-', ['&Preview', '&Firefox'], 'ff')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Firefox (New Window)'], 'nff')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Firefox (New Tab)'], 'tff')
endif
if maparg(g:htmlplugin.map_leader .. 'gc', 'n') != ''
  HTML#Menu('menu', '-', ['Preview', '-sep3-'], '<nop>')
  HTML#LeadMenu('amenu', '-', ['&Preview', '&Chrome'], 'gc')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Chrome (New Window)'], 'ngc')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Chrome (New Tab)'], 'tgc')
endif
if maparg(g:htmlplugin.map_leader .. 'ed', 'n') != ''
  HTML#Menu('menu', '-', ['Preview', '-sep4-'], '<nop>')
  HTML#LeadMenu('amenu', '-', ['&Preview', '&Edge'], 'ed')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Edge (New Window)'], 'ned')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Edge (New Tab)'], 'ted')
endif
if maparg(g:htmlplugin.map_leader .. 'oa', 'n') != ''
  HTML#Menu('menu', '-', ['Preview', '-sep5-'], '<nop>')
  HTML#LeadMenu('amenu', '-', ['&Preview', '&Opera'], 'oa')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Opera (New Window)'], 'noa')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Opera (New Tab)'], 'toa')
endif
if maparg(g:htmlplugin.map_leader .. 'sf', 'n') != ''
  HTML#Menu('menu', '-', ['Preview', '-sep6-'], '<nop>')
  HTML#LeadMenu('amenu', '-', ['&Preview', '&Safari'], 'sf')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Safari (New Window)'], 'nsf')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Safari (New Tab)'], 'tsf')
endif
if maparg(g:htmlplugin.map_leader .. 'ly', 'n') != ''
  HTML#Menu('menu', '-', ['Preview', '-sep7-'], '<nop>')
  HTML#LeadMenu('amenu', '-', ['&Preview', '&Lynx'], 'ly')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Lynx (New Window)'], 'nly')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Lynx (:terminal)'], 'tly')
endif
if maparg(g:htmlplugin.map_leader .. 'w3', 'n') != ''
  HTML#Menu('menu', '-', ['Preview', '-sep8-'], '<nop>')
  HTML#LeadMenu('amenu', '-', ['&Preview', '&w3m'], 'w3')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'w3m (New Window)'], 'nw3')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'w3m (:terminal)'], 'tw3')
endif
if maparg(g:htmlplugin.map_leader .. 'ln', 'n') != ''
  HTML#Menu('menu', '-', ['Preview', '-sep9-'], '<nop>')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Li&nks'], 'ln')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Links (New Window)'], 'nln')
  HTML#LeadMenu('amenu', '-', ['&Preview', 'Links (:terminal)'], 'tln')
endif

# Bring in the tags and entities menus and mappings at the same time:
HTML#ReadTags(true, true)
HTML#ReadEntities(true, true)

# Create the rest of the colors menu:
HTML.COLOR_LIST->mapnew((_, value) => HTML#ColorsMenu(value[0], value[1], value[2], value[3]))

g:htmlplugin.did_menus = true

endif
# ---------------------------------------------------------------------------

# ---- Finalize and Clean Up: ------------------------------------------- {{{1

b:htmlplugin.doing_internal_mappings = false

# Try to reduce support requests from users:  {{{
if !HTML#BoolVar('g:htmlplugin.did_old_variable_check') &&
    (exists('g:html_author_name') || exists('g:html_author_email')
    || exists('g:html_bgcolor') || exists('g:html_textcolor')
    || exists('g:html_alinkcolor') || exists('g:html_vlinkcolor')
    || exists('g:html_tag_case') || exists('g:html_map_leader')
    || exists('g:html_map_entity_leader') || exists('g:html_default_charset')
    || exists('g:html_template') || exists('g:no_html_map_override')
    || exists('g:no_html_maps') || exists('g:no_html_menu')
    || exists('g:no_html_toolbar') || exists('g:no_html_tab_mapping'))
  g:htmlplugin.did_old_variable_check = true
  var message = "You have set one of the old HTML plugin configuration variables.\n"
  .. "These variables are no longer used in favor of a new dictionary variable.\n\n"
  .. "Please refer to \":help html-variables\"."
  if message->confirm("&Help\n&Dismiss", 2, 'Warning') == 1
    help html-variables
    # Go to the previous window or everything gets messy:
    wincmd p
  endif
endif
if !HTML#BoolVar('g:htmlplugin.did_plugin_warning_check')
  g:htmlplugin.did_plugin_warning_check = true
  var files = 'ftplugin/html/HTML.vim'->findfile(&runtimepath, -1)
  if files->len() > 1
    var filesmatched = files->HTML#FilesWithMatch('https\?://christianrobinson.name/\%(\%(programming/\)\?vim/\)\?HTML/', 20)
    if filesmatched->len() > 1
      var message = "Multiple versions of the HTML plugin are installed.\n"
        .. "Locations:\n   " .. filesmatched->map((_, value) => value->fnamemodify(':~'))->join("\n   ")
        .. "\nIt is necessary that you remove old versions!\n"
        .. "(Don't forget about browser_launcher.vim/BrowserLauncher.vim and MangleImageTag.vim)"
      message->confirm('&Dismiss', 1, 'Warning')
    endif
  endif
endif
# }}}

# vim:tabstop=2:shiftwidth=0:expandtab:textwidth=78:formatoptions=croq2j:
# vim:foldmethod=marker:foldcolumn=4:comments=b\:#:commentstring=\ #\ %s:
