--------------------------------------------------------------------------------
--  CFM  :  C o n s o l e   F i l e   M a n a g e r
--------------------------------------------------------------------------------

---------------------------------------- imports from "curses" module

local Caddch     = require( "curses" ).addch
local Caddstr    = require( "curses" ).addstr
local Cclrtobot  = require( "curses" ).clrtobot
local Ccurs_set  = require( "curses" ).curs_set
local Cecho      = require( "curses" ).echo
local Cgetch     = require( "curses" ).getch
local Cgetstr    = require( "curses" ).getstr
local Cmove      = require( "curses" ).move

---------------------------------------- imports from "posix" module

local Paccess    = require( "posix" ).access
local Pchdir     = require( "posix" ).chdir
local Pchmod     = require( "posix" ).chmod
local Pgetcwd    = require( "posix" ).getcwd
local Pgetgroup  = require( "posix" ).getgroup
local Pgetpasswd = require( "posix" ).getpasswd
local Pglob      = require( "posix" ).glob
local Pmkdir     = require( "posix" ).mkdir
local Pmkstemp   = require( "posix" ).mkstemp
local Preadlink  = require( "posix" ).readlink
local Pstat      = require( "posix" ).stat

---------------------------------------- imports from standard Lua libraries

local Mmax       = math.max
local Mmin       = math.min
local Odate      = os.date
local Oexecute   = os.execute
local Sformat    = string.format
local Sgsub      = string.gsub
local Slower     = string.lower
local Smatch     = string.match
local Srep       = string.rep
local Ssub       = string.sub
local Tremove    = table.remove
local Tsort      = table.sort

---------------------------------------- special line-drawing characters

local Chline, Cbtee, Cttee, Cllcorner, Clrcorner, Culcorner, Curcorner, Cvline

---------------------------------------- top-level local variables

local activefields,  -- sequence of the fields being displayed
      colwidths,     -- table mapping fields to widths of their display columns
      rawtitles,     -- table mapping fields to titles, unformatted
      titles,        -- table mapping fields to titles, formatted
      typeflag,      -- table mapping item types to single-character classifiers
      KeyActions,    -- table mapping command characters to their functions
      numrows,       -- number of rows in screen window
      numcols,       -- number of columns in screen window
      numheadrows,   -- number of rows for display of header information
      numfootrows,   -- number of rows for display of footer information
      numitemrows,   -- number of rows for display of item information
      base,          -- current directory name
      basex,         -- exchange directory name
      filter,        -- current filter pattern, or 'nil' if none
      path,          -- current directory name plus 'filter' if any
      pathheader,    -- number of items in 'path' and actual value of 'path'
      Items,         -- sequence of items in 'path'
      focuspos,      -- position in 'Items' of focussed item
      errmsg,        -- current error message, or 'nil' if none
      running,       -- is 'cfm' still running ?
      fullsize,      -- use total size of directories ?
      showdotitems,  -- display the items whose names start with '.' ?
      sortfield,     -- field on which to sort
      sortup,        -- sort in ascending order ?
      tempprefix,    -- prefix for temporary filenames
      normalcolour,  -- colour for general items
      focuscolour,   -- colour for focussed item
      hicolour,      -- colour for titles and marks
      inputcolour,   -- colour for user input
      errmsgcolour,  -- colour for error messages
      Cstdscr,       -- standard screen window
      helptext       -- sequence of one-line help messages

--------------------------------------------------------------------------------

local function SetScreen( )

   local Ccolor_pair  = require( "curses" ).color_pair
   local Cinit_pair   = require( "curses" ).init_pair
   local Cinitscr     = require( "curses" ).initscr
   local Ckeypad      = require( "curses" ).keypad
   local Craw         = require( "curses" ).raw
   local Cnl          = require( "curses" ).nl
   local Cstart_color = require( "curses" ).start_color

   Cinitscr( )

   local CCOLOR_BLUE   = require( "curses" ).COLOR_BLUE
   local CCOLOR_CYAN   = require( "curses" ).COLOR_CYAN
   local CCOLOR_RED    = require( "curses" ).COLOR_RED
   local CCOLOR_WHITE  = require( "curses" ).COLOR_WHITE
   local CCOLOR_YELLOW = require( "curses" ).COLOR_YELLOW

   local CA_BOLD       = require( "curses" ).A_BOLD

   Ccurs_set( 0 )
   Cecho( false )
   Ckeypad( )
   Cnl( false )
   Craw( )
   Cstart_color( )

   Cinit_pair( 1, CCOLOR_WHITE,  CCOLOR_BLUE  )
   Cinit_pair( 2, CCOLOR_BLUE,   CCOLOR_WHITE )
   Cinit_pair( 3, CCOLOR_CYAN,   CCOLOR_BLUE  )
   Cinit_pair( 4, CCOLOR_YELLOW, CCOLOR_BLUE  )
   Cinit_pair( 5, CCOLOR_WHITE,  CCOLOR_RED   )

   normalcolour = Ccolor_pair( 1 )
   focuscolour  = Ccolor_pair( 2 ) + CA_BOLD
   hicolour     = Ccolor_pair( 3 ) + CA_BOLD
   inputcolour  = Ccolor_pair( 4 ) + CA_BOLD
   errmsgcolour = Ccolor_pair( 5 ) + CA_BOLD

   Cstdscr = require( "curses" ).stdscr( )

   Cstdscr:wbkgd( normalcolour )
   end

--------------------------------------------------------------------------------

local function SetConstants( )

   local Pgetpid = require( "posix" ).getpid

   Chline     = require( "curses" ).ACS_HLINE
   Cbtee      = require( "curses" ).ACS_BTEE
   Cttee      = require( "curses" ).ACS_TTEE
   Cllcorner  = require( "curses" ).ACS_LLCORNER
   Clrcorner  = require( "curses" ).ACS_LRCORNER
   Culcorner  = require( "curses" ).ACS_ULCORNER
   Curcorner  = require( "curses" ).ACS_URCORNER
   Cvline     = require( "curses" ).ACS_VLINE

   rawtitles  = { access = " ACCESS  ",
                  group  = "GROUP",
                  mtime  = " MODIFICATION TIME ",
                  name   = " NAME",
                  owner  = "OWNER",
                  size   = "SIZE" }

   tempprefix = "/tmp/cfm-" .. Pgetpid( "pid" ) .. "-"

   typeflag   = { [ "block device"     ] = ")",
                  [ "character device" ] = "(",
                  [ "directory"        ] = "/",
                  [ "fifo"             ] = "|",
                  [ "link"             ] = "@",
                  [ "regular"          ] = " ",
                  [ "socket"           ] = "=",
                  [ "?"                ] = "?" }

   helptext   = { " h   toggle display of this help screen",
                  " a   toggle display of field ACCESS",
                  " g   toggle display of field GROUP",
                  " o   toggle display of field OWNER",
                  " s   toggle display of field SIZE",
                  " t   toggle display of field MODIFICATION TIME",
                  " A   change ACCESS of selected item(s)",
                  " G   change GROUP  of selected item(s)",
                  " O   change OWNER  of selected item(s)",
                  " T   change MODIFICATION TIME of selected item(s)",
                  "^A   sort items by field ACCESS",
                  "^G   sort items by field GROUP",
                  "^N   sort items by field NAME",
                  "^O   sort items by field OWNER",
                  "^S   sort items by field SIZE",
                  "^T   sort items by field MODIFICATION TIME",
                  " c   copy selected item(s) to given destination",
                  " m   move selected item(s) to given destination",
                  " n   create a given new empty file",
                  " N   create a given new empty directory",
                  " q   quit CFM",
                  " r   run a given command",
                  " S   toggle usage of total directory size",
                  " u   update display",
                  " x   switch to target of 'copy' or 'move'",
                  " z   toggle marked status of one item",
                  " Z   toggle marked status of all items",
                  " /   display items matching a given filter",
                  " .   toggle display of hidden items",
                  " !   delete selected item(s)",
                  " $   launch a terminal emulator",
                  " ^   (arrow) scroll  up  one line",
                  " v   (arrow) scroll down up  one line",
                  " <   (arrow) go to parent directory",
                  " >   (arrow) enter directory or open file",
                  "PgDn scroll display forwards  by one screenful",
                  "PgUp scroll display backwards by one screenful",
                  "Home scroll display to begining",
                  "End  scroll display to end" }
   end

--------------------------------------------------------------------------------

local function MakeItem( itemname )

   local stat = Pstat( itemname )
   local type = stat.type
   local exec = type == "regular" and Paccess( itemname, "x" )

   return { rawname = itemname,
            type    = type,
            access  = stat.mode,
            group   = Pgetgroup( stat.gid ).name,
            marked  = false,
            mtime   = Odate( "%Y-%m-%d %H:%M:%S", stat.mtime ),
            name    = ( exec and "*" or typeflag[ type ] ) .. itemname,
            owner   = Pgetpasswd( stat.uid ).name,
            size    = tostring(
                         fullsize and io.popen( "du -bs '" .. itemname .. "'" )
                                         :read( "*n" )
                                  or  stat.size ) }
   end

--------------------------------------------------------------------------------

local function CompareItems( i1, i2 )

   local i1field, i2field = i1[ sortfield ], i2[ sortfield ]

   if sortup then
      return i1field < i2field or i1field == i2field and i1.rawname < i2.rawname
   else
      return i1field > i2field or i1field == i2field and i1.rawname < i2.rawname
      end
   end

--------------------------------------------------------------------------------

local function SetItems( )

   local maxlen = { }
   for k, v in pairs( rawtitles ) do
      maxlen[ k ] = #v
      end

   Items = { }

   if filter then
      for _, itemname in ipairs( Pglob( filter ) or { } ) do
         if itemname ~= "." and itemname ~= ".." then
            Items[ #Items + 1 ] = MakeItem( itemname )
            end
         end
   else
      if showdotitems then
         for _, itemname in ipairs( Pglob( ".[!.]*" ) or { } ) do
            Items[ #Items + 1 ] = MakeItem( itemname )
            end
         end
      for _, itemname in ipairs( Pglob( "*" ) or { } ) do
         Items[ #Items + 1 ] = MakeItem( itemname )
         end
      end

   pathheader = Sformat( "%4i : %s", #Items, path )

   for _, item in ipairs( Items ) do
      for k, v in pairs( maxlen ) do
         maxlen[ k ] = Mmax( v, #item[ k ] )
         end
      end

   local format = { }
   for k, v in pairs( maxlen ) do
      format[ k ] =
         " %" .. ( k ~= "size" and "-" or "" ) .. tostring( v ) .. "s "
      end

   titles    = { }
   colwidths = { }
   for k, v in pairs( rawtitles ) do
      titles[ k ]    = Sformat( format[ k ], v )
      colwidths[ k ] = #titles[ k ]
      end

   for _, item in ipairs( Items ) do
      for k, v in pairs( format ) do
         item[ k ] = Sformat( v, item[ k ] )
         end
      end

   Tsort( Items, CompareItems )
   end

--------------------------------------------------------------------------------

local function SetPath( newbase, newfilter )

   Pchdir( newbase )
   base   = Pgetcwd( )
   filter = newfilter
   path   = filter and base .. ( base == "/" and "" or "/" ) .. filter
                   or  base
   end

--------------------------------------------------------------------------------

local function ToggleActive( field )

   for i, f in ipairs( activefields ) do
      if f == field then
         Tremove( activefields, i )
         return
         end
      end

   activefields[ #activefields + 1 ] = field
   end

--------------------------------------------------------------------------------

local function Pos( searchname )

   for pos, item in ipairs( Items ) do
      if item.rawname == searchname then
         return pos
         end
      end

   return 1
   end

--------------------------------------------------------------------------------

local function ActionItems( )

   local actionitems = { }

   for _, item in ipairs( Items ) do
      if item.marked then
         actionitems[ #actionitems + 1 ] = item
         end
      end

   if #actionitems == 0 then
      actionitems = { Items[ focuspos ] }
      end

   return actionitems
   end

--------------------------------------------------------------------------------

local function Open( item )

   local itemname, itemtype = item.rawname, item.type

   if itemtype == "directory" then
      SetPath( itemname, nil )
      SetItems( )
      focuspos = 1

   elseif itemtype == "link" then
      local linkname = Preadlink( itemname )
      Open( { rawname = linkname, type = Pstat( linkname ).type } )

   elseif Smatch( itemname, "%.gz$" ) then
      local _, tempbase = Pmkstemp( tempprefix .. "XXXXXX" )
      local tempname    = tempbase .. "-" .. Ssub( itemname, 1, -4 )
      Oexecute( "gunzip -c " .. itemname .. " >" .. tempname )
      Pchmod( tempname, "a-w" )
      Open( { rawname = tempname, type = "regular" } )

   else
      local ext = Ssub( Smatch( itemname, "%.[^.]-$" ) or "", 2 )
      local cmd = OpenProg[ Slower( ext ) ]
      Oexecute( "( " .. Sgsub( cmd, "#", "'" .. itemname .. "'" ) .. " & )" )
      end
   end

--------------------------------------------------------------------------------

local function Output( str, colour )

   Cstdscr:attrset( colour )
   Caddstr( str )
   Cstdscr:standend( )
   end

--------------------------------------------------------------------------------

local function OutputFooter( str, colour )

   Cmove( numrows - 1, 0 )
   Output( str, colour )
   end

--------------------------------------------------------------------------------

local function Input( prompt )

   OutputFooter( Srep( " ", numcols ), normalcolour )
   OutputFooter( "  " .. prompt .. " : ", hicolour )
   Cstdscr:attrset( inputcolour )
   Cecho( true )
   Ccurs_set( 1 )
   local input = Cgetstr( )
   Ccurs_set( 0 )
   Cecho( false )
   Cstdscr:standend( )

   -- odd to do this here?
   if Ssub( input, 1, 1 ) == "~" then
      errmsg = "~-expansion not supported"
      input  = ""
      end

   return ( input ~= "" and input or nil )
   end

--------------------------------------------------------------------------------

local function UpdateDisplay( )

   Cmove( 0, 0 )
   Cclrtobot( )

   Output( pathheader, hicolour )

   Cmove( 1, 0 )
   Caddch( Culcorner )
   for i, field in ipairs( activefields ) do
      for j = 1, colwidths[ field ] do
         Caddch( Chline )
         end
      Caddch( i < #activefields and Cttee or Curcorner )
      end

   Cmove( 2, 0 )
   Caddch( Cvline )
   for _, field in ipairs( activefields ) do
      Output( titles[ field ], hicolour )
      Caddch( Cvline )
      end

   numrows, numcols = Cstdscr:getmaxyx( )
   numitemrows      = numrows - numheadrows - numfootrows
   local firstpos   = focuspos - ( focuspos - 1 ) % numitemrows
   local lastpos    = Mmin( firstpos + numitemrows - 1, #Items )
   local row        = numheadrows - 1

   for pos = firstpos, lastpos do
      row = row + 1
      Cmove( row, 0 )
      local item = Items[ pos ]
      if item.marked then
         Output( "#", hicolour )
      else
         Caddch( Cvline )
         end
      for _, field in ipairs( activefields ) do
         Output( item[ field ],
                 pos == focuspos and focuscolour or normalcolour )
         Caddch( Cvline )
         end
      end

   Cmove( numheadrows +
             ( #Items == 0 and 0 or ( lastpos - 1 ) % numitemrows + 1 ),
          0 )
   Caddch( Cllcorner )
   for i, field in ipairs( activefields ) do
      for j = 1, colwidths[ field ] do
         Caddch( Chline )
         end
      Caddch( i < #activefields and Cbtee or Clrcorner )
      end

   if errmsg then
      OutputFooter( " " .. errmsg .. " ", errmsgcolour )
      end
   end

--------------------------------------------------------------------------------

local function DisplayHelp( )

   Cmove( 0, 0 )
   Cclrtobot( )

   Output( "KEY  ACTION", hicolour )

   for row, text in ipairs( helptext ) do
      Cmove( row, 0 )
      Output( text, normalcolour )
      end
   end

--------------------------------------------------------------------------------

local function SetSortField( field )

   if sortfield == field then
      sortup = not sortup
   else
      sortfield = field
      sortup    = true
      end
   SetItems( )
   focuspos = 1
   end

--------------------------------------------------------------------------------

local function SetKeyActions( )

   local Kdown  = require( "curses" ).KEY_DOWN
   local Kend   = require( "curses" ).KEY_END
   local Khome  = require( "curses" ).KEY_HOME
   local Kleft  = require( "curses" ).KEY_LEFT
   local Knpage = require( "curses" ).KEY_NPAGE
   local Kppage = require( "curses" ).KEY_PPAGE
   local Kright = require( "curses" ).KEY_RIGHT
   local Kup    = require( "curses" ).KEY_UP

   KeyActions =
   {
      a          = function( )
                      ToggleActive( "access" )
                      end,

      A          = function( )
                      if #Items > 0 then
                         local newaccess = Input( "NEW ACCESS MODES" )
                         if newaccess then
                            local option
                            if Ssub( newaccess, 1, 1 ) == "*" then
                               option    = "-R "
                               newaccess = Ssub( newaccess, 2 )
                            else
                               option = ""
                               end
                            for _, item in ipairs( ActionItems( ) ) do
                               Oexecute( "chmod " .. option .. newaccess .. " '"
                                         .. item.rawname .. "'" )
                               end
                            SetItems( )
                            end
                         end
                      end,

      c          = function( )
                      if #Items > 0 then
                         local target = Input( "COPY TO" )
                         if target then
                            for _, item in ipairs( ActionItems( ) ) do
                               Oexecute( "cp -R '" .. item.rawname .. "' '" ..
                                         target .. "'" )
                               end
                            SetItems( )
                            focuspos = Pos( target )
                            -- ### HACK!  basex = dirname( path( target ) )
                            basex = base .. "/" .. target
                            end
                         end
                      end,

      g          = function( )
                      ToggleActive( "group" )
                      end,

      G          = function( )
                      if #Items > 0 then
                         local newgroup = Input( "CHANGE GROUP TO" )
                         if newgroup then
                            local option
                            if Ssub( newgroup, 1, 1 ) == "*" then
                               option   = "-R "
                               newgroup = Ssub( newgroup, 2 )
                            else
                               option = ""
                               end
                            for _, item in ipairs( ActionItems( ) ) do
                               Oexecute( "chgrp " .. option .. newgroup .. " '"
                                         .. item.rawname .. "'" )
                               end
                            SetItems( )
                            end
                         end
                      end,

      h          = function( )
                      DisplayHelp( )
                      repeat
                         until Cgetch( ) == 'h'
                      end,

      m          = function( )
                      if #Items > 0 then
                         local target = Input( "MOVE TO" )
                         if target then
                            for _, item in ipairs( ActionItems( ) ) do
                               Oexecute( "mv '" .. item.rawname .. "' '" ..
                                         target .. "'" )
                               end
                            SetItems( )
                            focuspos = Mmax( Mmin( focuspos, #Items ), 1 )
                            -- ### HACK!  basex = dirname( path( target ) )
                            basex = base .. "/" .. target
                            end
                         end
                      end,

      n          = function( )
                      local newname = Input( "NAME OF NEW FILE" )
                      if newname then
                         Oexecute( "touch '" .. newname .. "'" )
                         SetItems( )
                         focuspos = Pos( newname )
                         end
                      end,

      N          = function( )
                      local newname = Input( "NAME OF NEW DIRECTORY" )
                      if newname then
                         Pmkdir( newname )
                         SetItems( )
                         focuspos = Pos( newname )
                         end
                      end,

      o          = function( )
                      ToggleActive( "owner" )
                      end,

      O          = function( )
                      if #Items > 0 then
                         local newowner = Input( "CHANGE OWNER TO" )
                         if newowner then
                            local option
                            if Ssub( newowner, 1, 1 ) == "*" then
                               option   = "-R "
                               newowner = Ssub( newowner, 2 )
                            else
                               option = ""
                               end
                            for _, item in ipairs( ActionItems( ) ) do
                               Oexecute( "chown " .. option .. newowner .. " '"
                                         .. item.rawname .. "'" )
                               end
                            SetItems( )
                            end
                         end
                      end,

      q          = function( )
                      running = false
                      end,

      r          = function( )
                      if #Items > 0 then
                         local pattern = Input( "PATTERN" )
                         if pattern then
                            local match   = Sgsub( pattern, "%*", "(.*)" )
                            local command = Input( "COMMAND" )
                            if command then
                               for _, item in ipairs( ActionItems( ) ) do
                                  local itemname = item.rawname
                                  local piece    = Smatch( itemname, match )
                                  if piece then
                                     Oexecute(
                                        Sgsub( Sgsub( command, "#", itemname ),
                                               "*",
                                               piece ) )
                                     end
                                  end
                               end
                            end
                         SetItems( )
                         end
                      end,

      s          = function( )
                      ToggleActive( "size" )
                      end,

      S          = function( )
                      fullsize = not fullsize
                      SetItems( )
                      end,

      t          = function( )
                      ToggleActive( "mtime" )
                      end,

      T          = function( )
                      if #Items > 0 then
                         local newtime = Input( "NEW TIME" )
                         if newtime then
                            local timearg = newtime == "now"
                                               and ""
                                               or  "-d '" .. newtime .. "'"
                            for _, item in ipairs( ActionItems( ) ) do
                               Oexecute( "touch " .. timearg .. "'" ..
                                         item.rawname .. "'" )
                               end
                            SetItems( )
                            end
                         end
                      end,

      u          = function( )
                      SetItems( )
                      end,

      x          = function( )
                      base, basex = basex, base
                      SetPath( base, nil )
                      SetItems( )
                      end,

      z          = function( )
                      if #Items > 0 then
                         local item = Items[ focuspos ]
                         item.marked = not item.marked
                         end
                      end,

      Z          = function( )
                      local marking = true
                      for _, item in ipairs( Items ) do
                         if item.marked then
                            marking = false
                            break
                            end
                         end
                      for _, item in ipairs( Items ) do
                         item.marked = marking
                         end
                      end,

      [ '\001' ] = function( ) -- ^A
                      SetSortField( "access" )
                      end,

      [ '\007' ] = function( ) -- ^G
                      SetSortField( "group" )
                      end,

      [ '\014' ] = function( ) -- ^N
                      SetSortField( "rawname" )
                      end,

      [ '\015' ] = function( ) -- ^O
                      SetSortField( "owner" )
                      end,

      [ '\019' ] = function( ) -- ^S
                      SetSortField( "size" )
                      end,

      [ '\020' ] = function( ) -- ^T
                      SetSortField( "mtime" )
                      end,

      [ '/'    ] = function( )
                      if filter then
                         SetPath( base, nil )
                         SetItems( )
                         UpdateDisplay( )
                         end
                      local pattern = Input( "FILTER" )
                      if pattern then
                         SetPath( base, pattern )
                         SetItems( )
                         focuspos = 1
                         end
                      end,

      [ '.'    ] = function( )
                      showdotitems = not showdotitems
                      SetItems( )
                      focuspos = 1
                      end,

      [ '!'    ] = function( )
                      if #Items > 0 then
                         for _, item in ipairs( ActionItems( ) ) do
                            Oexecute( "rm -r '" .. item.rawname .. "'" )
                            end
                         SetItems( )
                         focuspos = Mmax( Mmin( focuspos, #Items ), 1 )
                         end
                      end,

      [ '$'    ] = function( )
                      Oexecute( terminal .. " &" )
                      end,

      [ Kright ] = function( )
                      if #Items > 0 then
                         Open( Items[ focuspos ] )
                         end
                      end,

      [ Kleft  ] = function( )
                      if path ~= "/" then
                         local childname = Smatch( path, "[^/]*$" )
                         SetPath( Smatch( path, ".*/" ), nil )
                         SetItems( )
                         focuspos = Pos( childname )
                         end
                      end,

      [ Kdown  ] = function( )
                      focuspos = Mmax( Mmin( focuspos + 1, #Items ), 1 )
                      end,

      [ Kup    ] = function( )
                      focuspos = Mmax( focuspos - 1, 1 )
                      end,

      [ Knpage ] = function( )
                      focuspos = Mmax( Mmin( focuspos + numitemrows, #Items ),
                                       1 )
                      end,

      [ Kppage ] = function( )
                      focuspos = Mmax( focuspos - numitemrows, 1 )
                      end,

      [ Khome  ] = function( )
                      focuspos = 1
                      end,

      [ Kend   ] = function( )
                      focuspos = Mmax( #Items, 1 )
                      end,
   }

   setmetatable( KeyActions, { __index = function( )
                                            return function( ) end
                                            end } )
   end

--------------------------------------------------------------------------------

local function SetOptions( )

   local Ogetenv = os.getenv

   dofile( Ogetenv( "CFMRC" ) )

   setmetatable( OpenProg, { __index = function( )
                                          return OpenProg[ "*" ]
                                          end } )
   end

--------------------------------------------------------------------------------

local function InitVars( )

   activefields = { "name" }
   basex        = "."
   focuspos     = 1
   fullsize     = false
   numheadrows  = 3
   numfootrows  = 2
   running      = true
   showdotitems = false
   sortfield    = "rawname"
   sortup       = true

   SetPath( ".", nil )
   SetItems( )
   end

--------------------------------------------------------------------------------

local function Setup( )

   SetScreen( )
   SetConstants( )
   SetKeyActions( )
   SetOptions( )
   InitVars( )
   end

--------------------------------------------------------------------------------

local function ReadKey( )

   local key = Cgetch( )

   errmsg = nil

   return key
   end

--------------------------------------------------------------------------------

local function CloseDown( )

   local Cendwin = require( "curses" ).endwin

   Cendwin( )
   Oexecute( "rm -f " .. tempprefix .. "*" )
   end

--------------------------------------------------------------------------------

Setup( )

while running do
   UpdateDisplay( )
   KeyActions[ ReadKey( ) ]( )
   end

CloseDown( )

--------------------------------------------------------------------------------
