-- vim: ft=teal expandtab sw=3 ts=3

require("octo.model.octo-buffer")

-- Custom changes
global octo_repo_issues: any
global octo_buffers: {number: OctoBuffer}


-- Copied from https://github.com/teal-language/teal-types/blob/master/types/neovim/vim.d.tl

global record vim
   -- TODO: Either find a way to generate these or at least find a comprehensive list to put a bunch of 'TODO' stub definitions here
   --    Sadly, there doesn't seem to be a nice way to serialize all of these
   --    since they're lazily brought in as you call them
   --    this might be the only way since user defined functions are also called here
   --    ex vim.fn["MyPlugin#MyFunction"]() so
   -- VIM_fn = record -- if record maps were a thing
   --    {string:function(...: any): (any)}
   --    mode: function(): Mode
   --    ...
   -- end

   -- TODO:
   -- vim.treesitter

   fn: {string:function(...: any): (any)}
   cmd: function(cmd: string)
   call: function(func: string, ...: any)
   call: function(string, ...: any): any

   enum Mode
      "n" -- Normal
      "no" -- Operator-pending
      "nov" -- Operator-pending (forced charwise |o_v|)
      "noV" -- Operator-pending (forced linewise |o_V|)
      "no" -- Operator-pending (forced blockwise |o_CTRL-V|)
      "niI" -- Normal using |i_CTRL-O| in |Insert-mode|
      "niR" -- Normal using |i_CTRL-O| in |Replace-mode|
      "niV" -- Normal using |i_CTRL-O| in |Virtual-Replace-mode|
      "v" -- Visual by character
      "V" -- Visual by line
      "" -- Visual blockwise
      "s" -- Select by character
      "S" -- Select by line
      "" -- Select blockwise
      "i" -- Insert
      "ic" -- Insert mode completion |compl-generic|
      "ix" -- Insert mode |i_CTRL-X| completion
      "R" -- Replace |R|
      "Rc" -- Replace mode completion |compl-generic|
      "Rv" -- Virtual Replace |gR|
      "Rx" -- Replace mode |i_CTRL-X| completion
      "c" -- Command-line editing
      "cv" -- Vim Ex mode |gQ|
      "ce" -- Normal Ex mode |Q|
      "r" -- Hit-enter prompt
      "rm" -- The -- more -- prompt
      "r?" -- |:confirm| query of some sort
      "!" -- Shell or external command is executing
      "t" -- Terminal mode: keys go to the job
   end

   record InspectOptions
      depth: integer
      newline: string
      indent: string
      process: function
   end
   inspect: function(any, InspectOptions): string

   record log
      record levels
         DEBUG: integer
         INFO: integer
         HINT: integer
         WARN: integer
         ERROR: integer
      end
   end
   notify: function(msg: string, log_level: integer, opts: table)
   notify_once: function(msg:string, level:integer, opt:table)
   paste: function({string}, integer): boolean
   schedule_wrap: function(function): function
   deep_equal: function(any, any): boolean
   deepcopy: function<T>(T): T
   defer_fn: function(function, integer)
   startswith: function(string, string): boolean
   endswith: function(string, string): boolean
   gsplit: function(string, string, boolean): function(): string
   is_callable: function(any): boolean
   list_extend: function<T>({T}, {T}, integer, integer): {T}
   list_extend: function<T, K>({T}, {K}, integer, integer): {T|K}
   list_slice: function<T>({T}, integer, integer): {T}
   pesc: function(string): string
   split: function(string, string, boolean): {string}
   wait: function(integer)

   tbl_add_reverse_lookup: function(table)
   tbl_contains: function<T>({T}, T): boolean

   tbl_count: function(table): integer

   enum ExtendBehavior
      "error"
      "keep"
      "force"
   end
   tbl_extend: function(ExtendBehavior, table, table, ...: table): table
   tbl_extend: function<T>(ExtendBehavior, {T:any}, {T:any}, ...: {T:any}): {T:any}
   tbl_extend: function<T>(ExtendBehavior, {any:T}, {any:T}, ...: {any:T}): {any:T}
   tbl_extend: function<T,V>(ExtendBehavior, {T:V}, {T:V}, ...: {T:V}): {T:V}
   tbl_deep_extend: function(ExtendBehavior, table, table, ...: table): table
   tbl_deep_extend: function<T>(ExtendBehavior, {T:any}, {T:any}, ...: {T:any}): {T:any}
   tbl_deep_extend: function<T>(ExtendBehavior, {any:T}, {any:T}, ...: {any:T}): {any:T}
   tbl_deep_extend: function<T,V>(ExtendBehavior, {T:V}, {T:V}, ...: {T:V}): {T:V}

   tbl_filter: function<T>(function(T): (boolean), {T})
   tbl_filter: function(function(any): (boolean), {any})

   tbl_flatten: function<T>({T|{T}}): {T}
   tbl_flatten: function({any|{any}}): {any}

   tbl_isempty: function(table): boolean

   tbl_islist: function(table): boolean

   tbl_keys: function<T>({T:any}): {T}

   tbl_values: function<T>({any:T}): {T}

   tbl_map: function<A, B, C>(function(B): (C), {A:B}): {A:C}
   tbl_map: function(function(any): (any), table): table

   trim: function(string): string

   enum TypeName
      "table" "t"
      "string" "s"
      "number" "n"
      "boolean" "b"
      "function" "f"
      "nil"
      "thread"
      "userdata"
   end
   -- Technically, this should be a union of tuples since the types are dependent and this allows for invalid combos
   validate: function({string:{any, TypeName | function(any): (boolean, string), boolean | string}})
   -- should be {string:{any, TypeName, boolean} | {any, function(any): (boolean, string)}, string}}

   record Regex
      match_str: function(Regex, string): integer, integer
      match_line: function(Regex, integer, integer, integer, integer): integer, integer
   end
   regex: function(string): Regex

   diff: function(a:string, b:string):string
   -- TODO
   -- diff: function(a:string, b:string, options:DiffOptions):string | {integer}

   record VersionInfo
      api_compatible:integer
      api_level:integer
      api_prerelease:integer
      major:integer
      minor:integer
      patch:integer
   end

   version:function():VersionInfo

   uri_from_bufnr:function(bufnr:integer):string
   uri_from_fname:function(path:string):string
   uri_to_bufnr:function(uri:string):integer
   uri_to_fname:function(uri:string):string

   pretty_print:function(obj:any):string

   region:function(bufnr:integer, pos1:{integer}, pos2:{integer}, regtype:string, inclusive:boolean):{integer:{integer}}

   record filetype
      -- TODO - replace table with options record
      add: function(filetypes:table)

      match: function(name:string, bufnr:integer)
   end

   record mpack
      encode: function(obj:any):string
      decode: function(str:string):any
   end

   record spell
      check: function(str:string):{{string | integer}}
   end

   -- TODO: these are a pitiful approximation of luv's types
   -- once Teal has some form of type inheritance/composition and luv.d.tl is written
   -- just steal from that
   record loop
      cwd: function(): string
      sleep: function(integer)
      record Handle
         close: function(Handle)
         is_closing: function(Timer)
      end
      record Pipe
         read_start: function(Pipe, function(string, string))
         read_stop: function(Pipe)
         close: function(Pipe)
      end
      record Process
         close: function(Process)
      end
      record Timer
         start: function(Timer, integer, integer, function)
         close: function(Timer)
         stop: function(Timer)
         is_closing: function(Timer)
      end
      new_timer: function(): Timer

      new_pipe: function(boolean): Pipe

      -- TODO: the rest of these
      record SpawnOptions
         cwd: string
         args: {string}
         stdio: {Pipe, Pipe, Pipe}
      end
      spawn: function(string, SpawnOptions, function): Process

      read_start: function(Pipe, function(string, string))

      record FsStat
         record Time
            sec: integer
            nsec: integer
         end
         dev: integer
         mode: integer
         nlink: integer
         uid: integer
         gid: integer
         rdev: integer
         ino: integer
         size: integer
         blksize: integer
         blocks: integer
         flags: integer
         gen: integer
         atime: Time
         mtime: Time
         ctime: Time
         birthtime: Time
         type: string
      end
      fs_stat: function(string): FsStat, string, string
      fs_stat: function(string, function(string, FsStat))

      fs_lstat: function(string): FsStat, string, string
      fs_lstat: function(string, function(string, FsStat))

      fs_fstat: function(integer): FsStat, string, string
      fs_fstat: function(integer, function(string, FsStat))

      record Dir userdata end
      fs_scandir: function(string, function(string, Dir)): Dir, string, string
      fs_scandir_next: function(Dir): string, string, string

      fs_mkdir: function(string, integer, function(string, boolean)): boolean | Dir, string, string
   end

   in_fast_event: function(): boolean

   type NIL = record userdata end -- special nil for filling tables

   empty_dict: function(): table
   on_key: function(function(string), integer): integer

   rpcnotify: function(integer, string, ...: string)
   rpcrequest: function(integer, string, ...: string)

   stricmp: function(string, string): integer
   str_utfindex: function(string, integer): integer, integer
   str_byteindex: function(string, integer, boolean): integer

   schedule: function(function)

   schedule_wrap: function(function): function

   type_idx: boolean

   val_idx: boolean

   types: {string|integer:string|integer}

   record KeyMap
      record DelOptions
         buffer:boolean
      end

      record SetOptions
         unique:boolean
         expr:boolean
         script:boolean
         nowait:boolean
         remap:boolean
         replace_keycodes:boolean
         silent:boolean
         buffer:boolean
      end

      set:function(mode:string|{string}, lhs:string, rhs:string|function(), opts:SetOptions)
      del:function(modes:string|{string}, lhs:string, opts:DelOptions)
   end

   keymap: KeyMap

   record EventData --TODO: this is a vim thing, so types aren't really documented
      abort: any
      chan: integer
      cmdlevel: any
      cmdtype: any
      cwd: string
      inclusive: boolean
      scope: any
      operator: any
      regcontents: any
      regname: any
      regtype: any
      visual: any
      completed_item: any
      height: any
      width: any
      row: integer
      col: integer
      size: any
      scrollbar: any
      changed_window: any
   end

   record highlight
      record Opts
         higroup: string
         timeout: integer
         on_macro: boolean
         on_visual: boolean
         event: EventData
      end
      on_yank: function(Opts)
      range: function(
         bufnr: integer,
         ns: integer,
         higroup: string,
         start: {integer, integer},
         finish: {integer, integer},
         rtype: any,
         inclusive: boolean
      )
   end

   record diagnostic
      record Severity -- would be great if this could be a tuplerecord
         {string}
         ERROR: integer
         WARN: integer
         INFO: integer
         HINT: integer
         E: integer
         W: integer
         I: integer
         H: integer
      end
      severity: Severity

      record Diagnostic
         lnum: integer -- The starting line of the diagnostic
         end_lnum: integer -- The final line of the diagnostic
         col: integer -- The starting column of the diagnostic
         end_col: integer -- The final column of the diagnostic
         severity: integer -- The severity of the diagnostic |vim.diagnostic.severity|
         message: string -- The diagnostic text
         source: string -- The source of the diagnostic
      end
      record ConfigOpts
         record UnderlineOpts
            severity: integer -- vim.diagnostic.severity
         end
         record VirtualTextOpts
            severity: integer -- vim.diagnostic.severity
            source: string
            format: function(diagnostic: Diagnostic): string
         end
         record SignsOpts
            severity: integer
            priority: integer
         end

         underline: boolean|UnderlineOpts
         virtual_text: boolean|VirtualTextOpts
         signs: boolean|SignsOpts
         float: OpenFloatOpts
         update_in_insert: boolean
         severity_sort: boolean
      end
      record GetOpts
         namespace: integer
         lnum: integer
         severity: integer -- vim.diagnostic.severity
      end
      record GotoOpts
         namespace: integer
         cursor_position: {integer, integer}
         wrap: boolean
         severity: integer -- vim.diagnostic.severity
         float: boolean|OpenFloatOpts
         win_id: integer
      end
      record OpenFloatOpts
         enum Scope
            "buffer"
            "line"
            "cursor"
         end

         namespace: integer
         scope: Scope
         pos: integer|{integer, integer}
         severity_sort: boolean
         severity: integer -- vim.diagnostic.severity
         header: string|{string, string}
         source: string
         format: function(diagnostic: Diagnostic): string
         prefix: string|{string, string}|function(diagnostic: Diagnostic, i: integer, total: integer): string, string
      end
      record SetLocListOpts
         namespace: integer
         winnr: integer
         open: boolean
         title: string
         severity: integer -- vim.diagnostic.severity
      end
      record SetQfListOpts
         namespace: integer
         open: boolean
         title: string
         severity: integer -- vim.diagnostic.severity
      end
      config: function(opts: ConfigOpts, namespace: integer)
      disable: function(bufnr: integer, namespace: integer)
      enable: function(bufnr: integer, namespace: integer)
      fromqflist: function(list: {any}): {Diagnostic}
      get: function(bufnr: integer, opts: GetOpts)
      get_namespace: function(namespace: integer): {string:integer}
      get_namespace: function(namespace: integer): {{string:integer}}
      get_next: function(opts: GotoOpts): Diagnostic
      get_next_pos: function(opts: GotoOpts): {integer, integer}
      get_prev: function(opts: GotoOpts): Diagnostic
      get_prev_pos: function(opts: GotoOpts): {integer, integer}
      goto_next: function(opts: GotoOpts)
      goto_prev: function(opts: GotoOpts)
      hide: function(namespace: integer, bufnr: integer)
      match: function(str: string, pat: string, groups: {string}, severity_map: {string:string}, defaults: {string:any}): Diagnostic
      open_float: function(opts: OpenFloatOpts): {integer, integer}
      reset: function(namespace: integer, bufnr: integer)
      set: function(namespace: integer, bufnr: integer, diagnostics: {Diagnostic}, opts: ConfigOpts)
      setloclist: function(opts: SetLocListOpts)
      setqflist: function(opts: SetQfListOpts)
      show: function(namespace: integer, bufnr: integer, diagnostics: {Diagnostic}, opts: ConfigOpts)
      toqflist: function({Diagnostic}): {string:any}
   end

   record lsp
      record buf
         hover: function
      end
      buf_attach_client: function(bufnr: integer, client_id: integer)
      buf_get_clients: function(bufnr: integer)
      buf_is_attached: function(bufnr: integer, client_id: integer)
      buf_notify: function(bufnr: integer, method: string, params: string): boolean
      buf_request: function(bufnr: integer, method: string, params: table, handler: function): {integer:integer}, function
      buf_request_sync: function(bufnr: integer, method: string, params: table, timeout_ms: integer): {integer:integer}, string

      record Client
         request: function(Client)
      end
      client: function(): Client
   end

   -- TODO:
   -- vim.opt
   -- vim.opt_global
   -- vim.opt_local

   g: {string:any}
   t: {string:any}
   v: {string:any}
   b: {string:any}
   w: {string:any}
   env: {string:any}

   record AllOptions
      acd: boolean
      ai: boolean
      al: number
      aleph: number
      allowrevins: boolean
      ambiwidth: string
      ambw: string
      ar: boolean
      arab: boolean
      arabic: boolean
      arabicshape: boolean
      ari: boolean
      arshape: boolean
      autochdir: boolean
      autoindent: boolean
      autoread: boolean
      autowrite: boolean
      autowriteall: boolean
      aw: boolean
      awa: boolean
      background: string
      backspace: string
      backup: boolean
      backupcopy: string
      backupdir: string
      backupext: string
      backupskip: string
      bdir: string
      belloff: string
      bex: string
      bg: string
      bh: string
      bin: boolean
      binary: boolean
      bk: boolean
      bkc: string
      bl: boolean
      bo: string
      bomb: boolean
      breakat: string
      breakindent: boolean
      breakindentopt: string
      bri: boolean
      briopt: string
      brk: string
      browsedir: string
      bs: string
      bsdir: string
      bsk: string
      bt: string
      bufhidden: string
      buflisted: boolean
      buftype: string
      casemap: string
      cb: string
      cc: string
      ccv: string
      cd: string
      cdh: boolean
      cdhome: boolean
      cdpath: string
      cedit: string
      cf: boolean
      cfu: string
      ch: number
      channel: number
      charconvert: string
      ci: boolean
      cin: boolean
      cindent: boolean
      cink: string
      cinkeys: string
      cino: string
      cinoptions: string
      cinw: string
      cinwords: string
      clipboard: string
      cmdheight: number
      cmdwinheight: number
      cmp: string
      cms: string
      co: number
      cocu: string
      cole: number
      colorcolumn: string
      columns: number
      com: string
      comments: string
      commentstring: string
      compatible: boolean
      complete: string
      completefunc: string
      completeopt: string
      completeslash: string
      concealcursor: string
      conceallevel: number
      confirm: boolean
      copyindent: boolean
      cot: string
      cp: boolean
      cpo: string
      cpoptions: string
      cpt: string
      crb: boolean
      cscopepathcomp: number
      cscopeprg: string
      cscopequickfix: string
      cscoperelative: boolean
      cscopetag: boolean
      cscopetagorder: number
      cscopeverbose: boolean
      csl: string
      cspc: number
      csprg: string
      csqf: string
      csre: boolean
      cst: boolean
      csto: number
      csverb: boolean
      cuc: boolean
      cul: boolean
      culopt: string
      cursorbind: boolean
      cursorcolumn: boolean
      cursorline: boolean
      cursorlineopt: string
      cwh: number
      debug: string
      deco: boolean
      def: string
      define: string
      delcombine: boolean
      dex: string
      dg: boolean
      dict: string
      dictionary: string
      diff: boolean
      diffexpr: string
      diffopt: string
      digraph: boolean
      dip: string
      dir: string
      directory: string
      display: string
      dy: string
      ea: boolean
      ead: string
      eadirection: string
      eb: boolean
      ed: boolean
      edcompatible: boolean
      ef: string
      efm: string
      ei: string
      emo: boolean
      emoji: boolean
      enc: string
      encoding: string
      endofline: boolean
      eol: boolean
      ep: string
      equalalways: boolean
      equalprg: string
      errorbells: boolean
      errorfile: string
      errorformat: string
      et: boolean
      eventignore: string
      ex: boolean
      expandtab: boolean
      exrc: boolean
      fcl: string
      fcs: string
      fdc: string
      fde: string
      fdi: string
      fdl: number
      fdls: number
      fdm: string
      fdn: number
      fdo: string
      fdt: string
      fen: boolean
      fenc: string
      fencs: string
      fex: string
      ff: string
      ffs: string
      fic: boolean
      fileencoding: string
      fileencodings: string
      fileformat: string
      fileformats: string
      fileignorecase: boolean
      filetype: string
      fillchars: string
      fixendofline: boolean
      fixeol: boolean
      flp: string
      fml: number
      fmr: string
      fo: string
      foldclose: string
      foldcolumn: string
      foldenable: boolean
      foldexpr: string
      foldignore: string
      foldlevel: number
      foldlevelstart: number
      foldmarker: string
      foldmethod: string
      foldminlines: number
      foldnestmax: number
      foldopen: string
      foldtext: string
      formatexpr: string
      formatlistpat: string
      formatoptions: string
      formatprg: string
      fp: string
      fs: boolean
      fsync: boolean
      ft: string
      gcr: string
      gd: boolean
      gdefault: boolean
      gfm: string
      gfn: string
      gfw: string
      go: string
      gp: string
      grepformat: string
      grepprg: string
      gtl: string
      gtt: string
      guicursor: string
      guifont: string
      guifontwide: string
      guioptions: string
      guitablabel: string
      guitabtooltip: string
      helpfile: string
      helpheight: number
      helplang: string
      hf: string
      hh: number
      hi: number
      hid: boolean
      hidden: boolean
      highlight: string
      history: number
      hk: boolean
      hkmap: boolean
      hkmapp: boolean
      hkp: boolean
      hl: string
      hlg: string
      hls: boolean
      hlsearch: boolean
      ic: boolean
      icm: string
      icon: boolean
      iconstring: string
      ignorecase: boolean
      im: boolean
      imc: boolean
      imcmdline: boolean
      imd: boolean
      imdisable: boolean
      imi: number
      iminsert: number
      ims: number
      imsearch: number
      inc: string
      inccommand: string
      include: string
      includeexpr: string
      incsearch: boolean
      inde: string
      indentexpr: string
      indentkeys: string
      indk: string
      inex: string
      inf: boolean
      infercase: boolean
      insertmode: boolean
      is: boolean
      isf: string
      isfname: string
      isi: string
      isident: string
      isk: string
      iskeyword: string
      isp: string
      isprint: string
      joinspaces: boolean
      jop: string
      js: boolean
      jumpoptions: string
      keymap: string
      keymodel: string
      keywordprg: string
      km: string
      kmp: string
      kp: string
      langmap: string
      langmenu: string
      langnoremap: boolean
      langremap: boolean
      laststatus: number
      lazyredraw: boolean
      lbr: boolean
      lcs: string
      linebreak: boolean
      lines: number
      linespace: number
      lisp: boolean
      lispwords: string
      list: boolean
      listchars: string
      lm: string
      lmap: string
      lnr: boolean
      loadplugins: boolean
      lpl: boolean
      lrm: boolean
      ls: number
      lsp: number
      lw: string
      lz: boolean
      ma: boolean
      magic: boolean
      makeef: string
      makeencoding: string
      makeprg: string
      mat: number
      matchpairs: string
      matchtime: number
      maxcombine: number
      maxfuncdepth: number
      maxmapdepth: number
      maxmempattern: number
      mco: number
      mef: string
      menc: string
      menuitems: number
      mfd: number
      mh: boolean
      mis: number
      mkspellmem: string
      ml: boolean
      mle: boolean
      mls: number
      mmd: number
      mmp: number
      mod: boolean
      modeline: boolean
      modelineexpr: boolean
      modelines: number
      modifiable: boolean
      modified: boolean
      more: boolean
      mouse: string
      mousef: boolean
      mousefocus: boolean
      mousehide: boolean
      mousem: string
      mousemodel: string
      mouses: string
      mouseshape: string
      mouset: number
      mousetime: number
      mp: string
      mps: string
      msm: string
      nf: string
      nrformats: string
      nu: boolean
      number: boolean
      numberwidth: number
      nuw: number
      odev: boolean
      ofu: string
      omnifunc: string
      opendevice: boolean
      operatorfunc: string
      opfunc: string
      pa: string
      packpath: string
      para: string
      paragraphs: string
      paste: boolean
      pastetoggle: string
      patchexpr: string
      patchmode: string
      path: string
      pb: number
      pdev: string
      penc: string
      pex: string
      pexpr: string
      pfn: string
      ph: number
      pheader: string
      pi: boolean
      pm: string
      pmbcs: string
      pmbfn: string
      popt: string
      pp: string
      preserveindent: boolean
      previewheight: number
      previewwindow: boolean
      printdevice: string
      printencoding: string
      printexpr: string
      printfont: string
      printheader: string
      printmbcharset: string
      printmbfont: string
      printoptions: string
      prompt: boolean
      pt: string
      pumblend: number
      pumheight: number
      pumwidth: number
      pvh: number
      pvw: boolean
      pw: number
      pyx: number
      pyxversion: number
      qe: string
      qftf: string
      quickfixtextfunc: string
      quoteescape: string
      rdb: string
      rdt: number
      re: number
      readonly: boolean
      redrawdebug: string
      redrawtime: number
      regexpengine: number
      relativenumber: boolean
      remap: boolean
      report: number
      revins: boolean
      ri: boolean
      rightleft: boolean
      rightleftcmd: string
      rl: boolean
      rlc: string
      rnu: boolean
      ro: boolean
      rtp: string
      ru: boolean
      ruf: string
      ruler: boolean
      rulerformat: string
      runtimepath: string
      sb: boolean
      sbo: string
      sbr: string
      sc: boolean
      scb: boolean
      scbk: number
      scl: string
      scr: number
      scroll: number
      scrollback: number
      scrollbind: boolean
      scrolljump: number
      scrolloff: number
      scrollopt: string
      scs: boolean
      sd: string
      sdf: string
      sect: string
      sections: string
      secure: boolean
      sel: string
      selection: string
      selectmode: string
      sessionoptions: string
      sft: boolean
      sh: string
      shada: string
      shadafile: string
      shcf: string
      shell: string
      shellcmdflag: string
      shellpipe: string
      shellquote: string
      shellredir: string
      shellslash: boolean
      shelltemp: boolean
      shellxescape: string
      shellxquote: string
      shiftround: boolean
      shiftwidth: number
      shm: string
      shortmess: string
      showbreak: string
      showcmd: boolean
      showfulltag: boolean
      showmatch: boolean
      showmode: boolean
      showtabline: number
      shq: string
      si: boolean
      sidescroll: number
      sidescrolloff: number
      signcolumn: string
      siso: number
      sj: number
      slm: string
      sm: boolean
      smartcase: boolean
      smartindent: boolean
      smarttab: boolean
      smc: number
      smd: boolean
      so: number
      softtabstop: number
      sol: boolean
      sp: string
      spc: string
      spell: boolean
      spellcapcheck: string
      spellfile: string
      spelllang: string
      spelloptions: string
      spellsuggest: string
      spf: string
      spl: string
      splitbelow: boolean
      splitright: boolean
      spo: string
      spr: boolean
      sps: string
      sr: boolean
      srr: string
      ss: number
      ssl: boolean
      ssop: string
      sta: boolean
      stal: number
      startofline: boolean
      statusline: string
      stl: string
      stmp: boolean
      sts: number
      su: string
      sua: string
      suffixes: string
      suffixesadd: string
      sw: number
      swapfile: boolean
      swb: string
      swf: boolean
      switchbuf: string
      sxe: string
      sxq: string
      syn: string
      synmaxcol: number
      syntax: string
      tabline: string
      tabpagemax: number
      tabstop: number
      tag: string
      tagbsearch: boolean
      tagcase: string
      tagfunc: string
      taglength: number
      tagrelative: boolean
      tags: string
      tagstack: boolean
      tal: string
      tbidi: boolean
      tbs: boolean
      tc: string
      tenc: string
      termbidi: boolean
      termencoding: string
      termguicolors: boolean
      termpastefilter: string
      terse: boolean
      textwidth: number
      tf: boolean
      tfu: string
      tgc: boolean
      tgst: boolean
      thesaurus: string
      thesaurusfunc: string
      tildeop: boolean
      timeout: boolean
      timeoutlen: number
      title: boolean
      titlelen: number
      titleold: string
      titlestring: string
      tl: number
      tm: number
      to: boolean
      top: boolean
      tpf: string
      tpm: number
      tr: boolean
      ts: number
      tsr: string
      tsrfu: string
      ttimeout: boolean
      ttimeoutlen: number
      ttm: number
      ttyfast: boolean
      tw: number
      uc: number
      udf: boolean
      udir: string
      ul: number
      undodir: string
      undofile: boolean
      undolevels: number
      undoreload: number
      updatecount: number
      updatetime: number
      ur: number
      ut: number
      varsofttabstop: string
      vartabstop: string
      vb: boolean
      vbs: number
      vdir: string
      ve: string
      verbose: number
      verbosefile: string
      vfile: string
      vi: string
      viewdir: string
      viewoptions: string
      vif: string
      viminfo: string
      viminfofile: string
      virtualedit: string
      visualbell: boolean
      vop: string
      vsts: string
      vts: string
      wa: boolean
      wak: string
      warn: boolean
      wb: boolean
      wc: number
      wcm: number
      wd: number
      wfh: boolean
      wfw: boolean
      wh: number
      whichwrap: string
      wi: number
      wic: boolean
      wig: string
      wildchar: number
      wildcharm: number
      wildignore: string
      wildignorecase: boolean
      wildmenu: boolean
      wildmode: string
      wildoptions: string
      wim: string
      winaltkeys: string
      winbl: number
      winblend: number
      window: number
      winfixheight: boolean
      winfixwidth: boolean
      winheight: number
      winhighlight: string
      winhl: string
      winminheight: number
      winminwidth: number
      winwidth: number
      wiw: number
      wm: number
      wmh: number
      wmnu: boolean
      wmw: number
      wop: string
      wrap: boolean
      wrapmargin: number
      wrapscan: boolean
      write: boolean
      writeany: boolean
      writebackup: boolean
      writedelay: number
      ws: boolean
      ww: string
   end
   o: AllOptions

   record GlobalOptions
      acd: boolean
      al: number
      aleph: number
      allowrevins: boolean
      ambiwidth: string
      ambw: string
      arabicshape: boolean
      ari: boolean
      arshape: boolean
      autochdir: boolean
      autowrite: boolean
      autowriteall: boolean
      aw: boolean
      awa: boolean
      background: string
      backspace: string
      backup: boolean
      backupdir: string
      backupext: string
      backupskip: string
      bdir: string
      belloff: string
      bex: string
      bg: string
      bk: boolean
      bo: string
      breakat: string
      brk: string
      browsedir: string
      bs: string
      bsdir: string
      bsk: string
      casemap: string
      cb: string
      ccv: string
      cd: string
      cdh: boolean
      cdhome: boolean
      cdpath: string
      cedit: string
      cf: boolean
      ch: number
      charconvert: string
      clipboard: string
      cmdheight: number
      cmdwinheight: number
      cmp: string
      co: number
      columns: number
      compatible: boolean
      completeopt: string
      completeslash: string
      confirm: boolean
      cot: string
      cp: boolean
      cpo: string
      cpoptions: string
      cscopepathcomp: number
      cscopeprg: string
      cscopequickfix: string
      cscoperelative: boolean
      cscopetag: boolean
      cscopetagorder: number
      cscopeverbose: boolean
      csl: string
      cspc: number
      csprg: string
      csqf: string
      csre: boolean
      cst: boolean
      csto: number
      csverb: boolean
      cwh: number
      debug: string
      deco: boolean
      delcombine: boolean
      dex: string
      dg: boolean
      diffexpr: string
      diffopt: string
      digraph: boolean
      dip: string
      dir: string
      directory: string
      display: string
      dy: string
      ea: boolean
      ead: string
      eadirection: string
      eb: boolean
      ed: boolean
      edcompatible: boolean
      ef: string
      ei: string
      emo: boolean
      emoji: boolean
      enc: string
      encoding: string
      equalalways: boolean
      errorbells: boolean
      errorfile: string
      eventignore: string
      ex: boolean
      exrc: boolean
      fcl: string
      fdls: number
      fdo: string
      fencs: string
      ffs: string
      fic: boolean
      fileencodings: string
      fileformats: string
      fileignorecase: boolean
      foldclose: string
      foldlevelstart: number
      foldopen: string
      fs: boolean
      fsync: boolean
      gcr: string
      gd: boolean
      gdefault: boolean
      gfm: string
      gfn: string
      gfw: string
      go: string
      grepformat: string
      gtl: string
      gtt: string
      guicursor: string
      guifont: string
      guifontwide: string
      guioptions: string
      guitablabel: string
      guitabtooltip: string
      helpfile: string
      helpheight: number
      helplang: string
      hf: string
      hh: number
      hi: number
      hid: boolean
      hidden: boolean
      highlight: string
      history: number
      hk: boolean
      hkmap: boolean
      hkmapp: boolean
      hkp: boolean
      hl: string
      hlg: string
      hls: boolean
      hlsearch: boolean
      ic: boolean
      icm: string
      icon: boolean
      iconstring: string
      ignorecase: boolean
      im: boolean
      imc: boolean
      imcmdline: boolean
      imd: boolean
      imdisable: boolean
      inccommand: string
      incsearch: boolean
      insertmode: boolean
      is: boolean
      isf: string
      isfname: string
      isi: string
      isident: string
      isp: string
      isprint: string
      joinspaces: boolean
      jop: string
      js: boolean
      jumpoptions: string
      keymodel: string
      km: string
      langmap: string
      langmenu: string
      langnoremap: boolean
      langremap: boolean
      laststatus: number
      lazyredraw: boolean
      lines: number
      linespace: number
      lm: string
      lmap: string
      lnr: boolean
      loadplugins: boolean
      lpl: boolean
      lrm: boolean
      ls: number
      lsp: number
      lz: boolean
      magic: boolean
      makeef: string
      mat: number
      matchtime: number
      maxcombine: number
      maxfuncdepth: number
      maxmapdepth: number
      maxmempattern: number
      mco: number
      mef: string
      menuitems: number
      mfd: number
      mh: boolean
      mis: number
      mkspellmem: string
      mle: boolean
      mls: number
      mmd: number
      mmp: number
      modelineexpr: boolean
      modelines: number
      more: boolean
      mouse: string
      mousef: boolean
      mousefocus: boolean
      mousehide: boolean
      mousem: string
      mousemodel: string
      mouses: string
      mouseshape: string
      mouset: number
      mousetime: number
      msm: string
      odev: boolean
      opendevice: boolean
      operatorfunc: string
      opfunc: string
      packpath: string
      para: string
      paragraphs: string
      paste: boolean
      pastetoggle: string
      patchexpr: string
      patchmode: string
      pb: number
      pdev: string
      penc: string
      pex: string
      pexpr: string
      pfn: string
      ph: number
      pheader: string
      pm: string
      pmbcs: string
      pmbfn: string
      popt: string
      pp: string
      previewheight: number
      printdevice: string
      printencoding: string
      printexpr: string
      printfont: string
      printheader: string
      printmbcharset: string
      printmbfont: string
      printoptions: string
      prompt: boolean
      pt: string
      pumblend: number
      pumheight: number
      pumwidth: number
      pvh: number
      pw: number
      pyx: number
      pyxversion: number
      qftf: string
      quickfixtextfunc: string
      rdb: string
      rdt: number
      re: number
      redrawdebug: string
      redrawtime: number
      regexpengine: number
      remap: boolean
      report: number
      revins: boolean
      ri: boolean
      rtp: string
      ru: boolean
      ruf: string
      ruler: boolean
      rulerformat: string
      runtimepath: string
      sb: boolean
      sbo: string
      sc: boolean
      scrolljump: number
      scrollopt: string
      scs: boolean
      sd: string
      sdf: string
      sect: string
      sections: string
      secure: boolean
      sel: string
      selection: string
      selectmode: string
      sessionoptions: string
      sft: boolean
      sh: string
      shada: string
      shadafile: string
      shcf: string
      shell: string
      shellcmdflag: string
      shellpipe: string
      shellquote: string
      shellredir: string
      shellslash: boolean
      shelltemp: boolean
      shellxescape: string
      shellxquote: string
      shiftround: boolean
      shm: string
      shortmess: string
      showcmd: boolean
      showfulltag: boolean
      showmatch: boolean
      showmode: boolean
      showtabline: number
      shq: string
      sidescroll: number
      sj: number
      slm: string
      sm: boolean
      smartcase: boolean
      smarttab: boolean
      smd: boolean
      sol: boolean
      sp: string
      spellsuggest: string
      splitbelow: boolean
      splitright: boolean
      spr: boolean
      sps: string
      sr: boolean
      srr: string
      ss: number
      ssl: boolean
      ssop: string
      sta: boolean
      stal: number
      startofline: boolean
      stmp: boolean
      su: string
      suffixes: string
      swb: string
      switchbuf: string
      sxe: string
      sxq: string
      tabline: string
      tabpagemax: number
      tagbsearch: boolean
      taglength: number
      tagrelative: boolean
      tagstack: boolean
      tal: string
      tbidi: boolean
      tbs: boolean
      tenc: string
      termbidi: boolean
      termencoding: string
      termguicolors: boolean
      termpastefilter: string
      terse: boolean
      tf: boolean
      tgc: boolean
      tgst: boolean
      tildeop: boolean
      timeout: boolean
      timeoutlen: number
      title: boolean
      titlelen: number
      titleold: string
      titlestring: string
      tl: number
      tm: number
      to: boolean
      top: boolean
      tpf: string
      tpm: number
      tr: boolean
      ttimeout: boolean
      ttimeoutlen: number
      ttm: number
      ttyfast: boolean
      uc: number
      udir: string
      undodir: string
      undoreload: number
      updatecount: number
      updatetime: number
      ur: number
      ut: number
      vb: boolean
      vbs: number
      vdir: string
      verbose: number
      verbosefile: string
      vfile: string
      vi: string
      viewdir: string
      viewoptions: string
      vif: string
      viminfo: string
      viminfofile: string
      visualbell: boolean
      vop: string
      wa: boolean
      wak: string
      warn: boolean
      wb: boolean
      wc: number
      wcm: number
      wd: number
      wh: number
      whichwrap: string
      wi: number
      wic: boolean
      wig: string
      wildchar: number
      wildcharm: number
      wildignore: string
      wildignorecase: boolean
      wildmenu: boolean
      wildmode: string
      wildoptions: string
      wim: string
      winaltkeys: string
      window: number
      winheight: number
      winminheight: number
      winminwidth: number
      winwidth: number
      wiw: number
      wmh: number
      wmnu: boolean
      wmw: number
      wop: string
      wrapscan: boolean
      write: boolean
      writeany: boolean
      writebackup: boolean
      writedelay: number
      ws: boolean
      ww: string
   end
   go: GlobalOptions

   record BufferOptions
      ai: boolean
      ar: boolean
      autoindent: boolean
      autoread: boolean
      backupcopy: string
      bh: string
      bin: boolean
      binary: boolean
      bkc: string
      bl: boolean
      bomb: boolean
      bt: string
      bufhidden: string
      buflisted: boolean
      buftype: string
      cfu: string
      channel: number
      ci: boolean
      cin: boolean
      cindent: boolean
      cink: string
      cinkeys: string
      cino: string
      cinoptions: string
      cinw: string
      cinwords: string
      cms: string
      com: string
      comments: string
      commentstring: string
      complete: string
      completefunc: string
      copyindent: boolean
      cpt: string
      def: string
      define: string
      dict: string
      dictionary: string
      efm: string
      endofline: boolean
      eol: boolean
      ep: string
      equalprg: string
      errorformat: string
      et: boolean
      expandtab: boolean
      fenc: string
      fex: string
      ff: string
      fileencoding: string
      fileformat: string
      filetype: string
      fixendofline: boolean
      fixeol: boolean
      flp: string
      fo: string
      formatexpr: string
      formatlistpat: string
      formatoptions: string
      formatprg: string
      fp: string
      ft: string
      gp: string
      grepprg: string
      imi: number
      iminsert: number
      ims: number
      imsearch: number
      inc: string
      include: string
      includeexpr: string
      inde: string
      indentexpr: string
      indentkeys: string
      indk: string
      inex: string
      inf: boolean
      infercase: boolean
      isk: string
      iskeyword: string
      keymap: string
      keywordprg: string
      kmp: string
      kp: string
      lisp: boolean
      lispwords: string
      lw: string
      ma: boolean
      makeencoding: string
      makeprg: string
      matchpairs: string
      menc: string
      ml: boolean
      mod: boolean
      modeline: boolean
      modifiable: boolean
      modified: boolean
      mp: string
      mps: string
      nf: string
      nrformats: string
      ofu: string
      omnifunc: string
      pa: string
      path: string
      pi: boolean
      preserveindent: boolean
      qe: string
      quoteescape: string
      readonly: boolean
      ro: boolean
      scbk: number
      scrollback: number
      shiftwidth: number
      si: boolean
      smartindent: boolean
      smc: number
      softtabstop: number
      spc: string
      spellcapcheck: string
      spellfile: string
      spelllang: string
      spelloptions: string
      spf: string
      spl: string
      spo: string
      sts: number
      sua: string
      suffixesadd: string
      sw: number
      swapfile: boolean
      swf: boolean
      syn: string
      synmaxcol: number
      syntax: string
      tabstop: number
      tag: string
      tagcase: string
      tagfunc: string
      tags: string
      tc: string
      textwidth: number
      tfu: string
      thesaurus: string
      thesaurusfunc: string
      ts: number
      tsr: string
      tsrfu: string
      tw: number
      udf: boolean
      ul: number
      undofile: boolean
      undolevels: number
      varsofttabstop: string
      vartabstop: string
      vsts: string
      vts: string
      wm: number
      wrapmargin: number
   end
   bo: BufferOptions

   record WindowOptions
      arab: boolean
      arabic: boolean
      breakindent: boolean
      breakindentopt: string
      bri: boolean
      briopt: string
      cc: string
      cocu: string
      cole: number
      colorcolumn: string
      concealcursor: string
      conceallevel: number
      crb: boolean
      cuc: boolean
      cul: boolean
      culopt: string
      cursorbind: boolean
      cursorcolumn: boolean
      cursorline: boolean
      cursorlineopt: string
      diff: boolean
      fcs: string
      fdc: string
      fde: string
      fdi: string
      fdl: number
      fdm: string
      fdn: number
      fdt: string
      fen: boolean
      fillchars: string
      fml: number
      fmr: string
      foldcolumn: string
      foldenable: boolean
      foldexpr: string
      foldignore: string
      foldlevel: number
      foldmarker: string
      foldmethod: string
      foldminlines: number
      foldnestmax: number
      foldtext: string
      lbr: boolean
      lcs: string
      linebreak: boolean
      list: boolean
      listchars: string
      nu: boolean
      number: boolean
      numberwidth: number
      nuw: number
      previewwindow: boolean
      pvw: boolean
      relativenumber: boolean
      rightleft: boolean
      rightleftcmd: string
      rl: boolean
      rlc: string
      rnu: boolean
      sbr: string
      scb: boolean
      scl: string
      scr: number
      scroll: number
      scrollbind: boolean
      scrolloff: number
      showbreak: string
      sidescrolloff: number
      signcolumn: string
      siso: number
      so: number
      spell: boolean
      statusline: string
      stl: string
      ve: string
      virtualedit: string
      wfh: boolean
      wfw: boolean
      winbl: number
      winblend: number
      winfixheight: boolean
      winfixwidth: boolean
      winhighlight: string
      winhl: string
      wrap: boolean
   end
   wo: WindowOptions

   record api
      --[[
         API version Information
            neovim version: 0.7.0

            compatible: 0
            level: 9
            prerelease: true
      --]]

      --[[
         Vim Type -> Teal Type
         Boolean -> boolean
         Buffer -> integer
         Dictionary -> {string:any}
         Float -> number
         Integer -> integer
         Number -> number
         String -> string
         Tabpage -> integer
         Window -> integer
         none of the above -> any
      --]]

      nvim_add_user_command: function(string--[[String]], any--[[Object]], {string:any}--[[Dictionary]])--[[void]]
      nvim_buf_add_highlight: function(integer--[[Buffer]], integer--[[Integer]], string--[[String]], integer--[[Integer]], integer--[[Integer]], integer--[[Integer]]): integer--[[Integer]]
      nvim_buf_add_user_command: function(integer--[[Buffer]], string--[[String]], any--[[Object]], {string:any}--[[Dictionary]])--[[void]]
      nvim_buf_attach: function(integer--[[Buffer]], boolean--[[Boolean]], {string:any}--[[Dictionary]]): boolean--[[Boolean]]
      nvim_buf_call: function(integer--[[Buffer]], any--[[LuaRef]]): any--[[Object]]
      nvim_buf_clear_namespace: function(integer--[[Buffer]], integer--[[Integer]], integer--[[Integer]], integer--[[Integer]])--[[void]]
      nvim_buf_del_extmark: function(integer--[[Buffer]], integer--[[Integer]], integer--[[Integer]]): boolean--[[Boolean]]
      nvim_buf_del_keymap: function(integer--[[Buffer]], string--[[String]], string--[[String]])--[[void]]
      nvim_buf_del_mark: function(integer--[[Buffer]], string--[[String]]): boolean--[[Boolean]]
      nvim_buf_del_user_command: function(integer--[[Buffer]], string--[[String]])--[[void]]
      nvim_buf_del_var: function(integer--[[Buffer]], string--[[String]])--[[void]]
      nvim_buf_delete: function(integer--[[Buffer]], {string:any}--[[Dictionary]])--[[void]]
      nvim_buf_detach: function(integer--[[Buffer]]): boolean--[[Boolean]]
      nvim_buf_get_changedtick: function(integer--[[Buffer]]): integer--[[Integer]]
      nvim_buf_get_commands: function(integer--[[Buffer]], {string:any}--[[Dictionary]]): {string:any}--[[Dictionary]]
      nvim_buf_get_extmark_by_id: function(integer--[[Buffer]], integer--[[Integer]], integer--[[Integer]], {string:any}--[[Dictionary]]): {integer}--[[ArrayOf(Integer)]]
      nvim_buf_get_extmarks: function(integer--[[Buffer]], integer--[[Integer]], any--[[Object]], any--[[Object]], {string:any}--[[Dictionary]]): any--[[Array]]
      nvim_buf_get_keymap: function(integer--[[Buffer]], string--[[String]]): {{string:any}}--[[ArrayOf(Dictionary)]]
      nvim_buf_get_lines: function(integer--[[Buffer]], integer--[[Integer]], integer--[[Integer]], boolean--[[Boolean]]): {string}--[[ArrayOf(String)]]
      nvim_buf_get_mark: function(integer--[[Buffer]], string--[[String]]): {integer,integer}--[[ArrayOf(Integer, 2)]]
      nvim_buf_get_name: function(integer--[[Buffer]]): string--[[String]]
      nvim_buf_get_offset: function(integer--[[Buffer]], integer--[[Integer]]): integer--[[Integer]]
      nvim_buf_get_option: function(integer--[[Buffer]], string--[[String]]): any--[[Object]]
      nvim_buf_get_text: function(integer--[[Buffer]], integer--[[Integer]], integer--[[Integer]], integer--[[Integer]], integer--[[Integer]], {string:any}--[[Dictionary]]): {string}--[[ArrayOf(String)]]
      nvim_buf_get_var: function(integer--[[Buffer]], string--[[String]]): any--[[Object]]
      nvim_buf_is_loaded: function(integer--[[Buffer]]): boolean--[[Boolean]]
      nvim_buf_is_valid: function(integer--[[Buffer]]): boolean--[[Boolean]]
      nvim_buf_line_count: function(integer--[[Buffer]]): integer--[[Integer]]
      nvim_buf_set_extmark: function(integer--[[Buffer]], integer--[[Integer]], integer--[[Integer]], integer--[[Integer]], {string:any}--[[Dictionary]]): integer--[[Integer]]
      nvim_buf_set_keymap: function(integer--[[Buffer]], string--[[String]], string--[[String]], string--[[String]], {string:any}--[[Dictionary]])--[[void]]
      nvim_buf_set_lines: function(integer--[[Buffer]], integer--[[Integer]], integer--[[Integer]], boolean--[[Boolean]], {string}--[[ArrayOf(String)]])--[[void]]
      nvim_buf_set_mark: function(integer--[[Buffer]], string--[[String]], integer--[[Integer]], integer--[[Integer]], {string:any}--[[Dictionary]]): boolean--[[Boolean]]
      nvim_buf_set_name: function(integer--[[Buffer]], string--[[String]])--[[void]]
      nvim_buf_set_option: function(integer--[[Buffer]], string--[[String]], any--[[Object]])--[[void]]
      nvim_buf_set_text: function(integer--[[Buffer]], integer--[[Integer]], integer--[[Integer]], integer--[[Integer]], integer--[[Integer]], {string}--[[ArrayOf(String)]])--[[void]]
      nvim_buf_set_var: function(integer--[[Buffer]], string--[[String]], any--[[Object]])--[[void]]
      nvim_call_atomic: function(any--[[Array]]): any--[[Array]]
      nvim_call_dict_function: function(any--[[Object]], string--[[String]], any--[[Array]]): any--[[Object]]
      nvim_call_function: function(string--[[String]], any--[[Array]]): any--[[Object]]
      nvim_chan_send: function(integer--[[Integer]], string--[[String]])--[[void]]
      nvim_clear_autocmds: function({string:any}--[[Dictionary]])--[[void]]
      nvim_command: function(string--[[String]])--[[void]]
      nvim_create_augroup: function(string--[[String]], {string:any}--[[Dictionary]]): integer--[[Integer]]
      nvim_create_autocmd: function(any--[[Object]], {string:any}--[[Dictionary]]): integer--[[Integer]]
      nvim_create_buf: function(boolean--[[Boolean]], boolean--[[Boolean]]): integer--[[Buffer]]
      nvim_create_namespace: function(string--[[String]]): integer--[[Integer]]
      nvim_del_augroup_by_id: function(integer--[[Integer]])--[[void]]
      nvim_del_augroup_by_name: function(string--[[String]])--[[void]]
      nvim_del_autocmd: function(integer--[[Integer]])--[[void]]
      nvim_del_current_line: function()--[[void]]
      nvim_del_keymap: function(string--[[String]], string--[[String]])--[[void]]
      nvim_del_mark: function(string--[[String]]): boolean--[[Boolean]]
      nvim_del_user_command: function(string--[[String]])--[[void]]
      nvim_del_var: function(string--[[String]])--[[void]]
      nvim_echo: function(any--[[Array]], boolean--[[Boolean]], {string:any}--[[Dictionary]])--[[void]]
      nvim_err_write: function(string--[[String]])--[[void]]
      nvim_err_writeln: function(string--[[String]])--[[void]]
      nvim_eval: function(string--[[String]]): any--[[Object]]
      nvim_eval_statusline: function(string--[[String]], {string:any}--[[Dictionary]]): {string:any}--[[Dictionary]]
      nvim_exec: function(string--[[String]], boolean--[[Boolean]]): string--[[String]]
      nvim_exec_autocmds: function(any--[[Object]], {string:any}--[[Dictionary]])--[[void]]
      nvim_exec_lua: function(string--[[String]], any--[[Array]]): any--[[Object]]
      nvim_feedkeys: function(string--[[String]], string--[[String]], boolean--[[Boolean]])--[[void]]
      nvim_get_all_options_info: function(): {string:any}--[[Dictionary]]
      nvim_get_api_info: function(): any--[[Array]]
      nvim_get_autocmds: function({string:any}--[[Dictionary]]): any--[[Array]]
      nvim_get_chan_info: function(integer--[[Integer]]): {string:any}--[[Dictionary]]
      nvim_get_color_by_name: function(string--[[String]]): integer--[[Integer]]
      nvim_get_color_map: function(): {string:any}--[[Dictionary]]
      nvim_get_commands: function({string:any}--[[Dictionary]]): {string:any}--[[Dictionary]]
      nvim_get_context: function({string:any}--[[Dictionary]]): {string:any}--[[Dictionary]]
      nvim_get_current_buf: function(): integer--[[Buffer]]
      nvim_get_current_line: function(): string--[[String]]
      nvim_get_current_tabpage: function(): integer--[[Tabpage]]
      nvim_get_current_win: function(): integer--[[Window]]
      nvim_get_hl_by_id: function(integer--[[Integer]], boolean--[[Boolean]]): {string:any}--[[Dictionary]]
      nvim_get_hl_by_name: function(string--[[String]], boolean--[[Boolean]]): {string:any}--[[Dictionary]]
      nvim_get_hl_id_by_name: function(string--[[String]]): integer--[[Integer]]
      nvim_get_keymap: function(string--[[String]]): {{string:any}}--[[ArrayOf(Dictionary)]]
      nvim_get_mark: function(string--[[String]], {string:any}--[[Dictionary]]): any--[[Array]]
      nvim_get_mode: function(): {string:any}--[[Dictionary]]
      nvim_get_namespaces: function(): {string:any}--[[Dictionary]]
      nvim_get_option: function(string--[[String]]): any--[[Object]]
      nvim_get_option_info: function(string--[[String]]): {string:any}--[[Dictionary]]
      nvim_get_option_value: function(string--[[String]], {string:any}--[[Dictionary]]): any--[[Object]]
      nvim_get_proc: function(integer--[[Integer]]): any--[[Object]]
      nvim_get_proc_children: function(integer--[[Integer]]): any--[[Array]]
      nvim_get_runtime_file: function(string--[[String]], boolean--[[Boolean]]): {string}--[[ArrayOf(String)]]
      nvim_get_var: function(string--[[String]]): any--[[Object]]
      nvim_get_vvar: function(string--[[String]]): any--[[Object]]
      nvim_input: function(string--[[String]]): integer--[[Integer]]
      nvim_input_mouse: function(string--[[String]], string--[[String]], string--[[String]], integer--[[Integer]], integer--[[Integer]], integer--[[Integer]])--[[void]]
      nvim_list_bufs: function(): {integer}--[[ArrayOf(Buffer)]]
      nvim_list_chans: function(): any--[[Array]]
      nvim_list_runtime_paths: function(): {string}--[[ArrayOf(String)]]
      nvim_list_tabpages: function(): {integer}--[[ArrayOf(Tabpage)]]
      nvim_list_uis: function(): any--[[Array]]
      nvim_list_wins: function(): {integer}--[[ArrayOf(Window)]]
      nvim_load_context: function({string:any}--[[Dictionary]]): any--[[Object]]
      nvim_notify: function(string--[[String]], integer--[[Integer]], {string:any}--[[Dictionary]]): any--[[Object]]
      nvim_open_term: function(integer--[[Buffer]], {string:any}--[[Dictionary]]): integer--[[Integer]]
      nvim_open_win: function(integer--[[Buffer]], boolean--[[Boolean]], {string:any}--[[Dictionary]]): integer--[[Window]]
      nvim_out_write: function(string--[[String]])--[[void]]
      nvim_parse_expression: function(string--[[String]], string--[[String]], boolean--[[Boolean]]): {string:any}--[[Dictionary]]
      nvim_paste: function(string--[[String]], boolean--[[Boolean]], integer--[[Integer]]): boolean--[[Boolean]]
      nvim_put: function({string}--[[ArrayOf(String)]], string--[[String]], boolean--[[Boolean]], boolean--[[Boolean]])--[[void]]
      nvim_replace_termcodes: function(string--[[String]], boolean--[[Boolean]], boolean--[[Boolean]], boolean--[[Boolean]]): string--[[String]]
      nvim_select_popupmenu_item: function(integer--[[Integer]], boolean--[[Boolean]], boolean--[[Boolean]], {string:any}--[[Dictionary]])--[[void]]
      nvim_set_client_info: function(string--[[String]], {string:any}--[[Dictionary]], string--[[String]], {string:any}--[[Dictionary]], {string:any}--[[Dictionary]])--[[void]]
      nvim_set_current_buf: function(integer--[[Buffer]])--[[void]]
      nvim_set_current_dir: function(string--[[String]])--[[void]]
      nvim_set_current_line: function(string--[[String]])--[[void]]
      nvim_set_current_tabpage: function(integer--[[Tabpage]])--[[void]]
      nvim_set_current_win: function(integer--[[Window]])--[[void]]
      nvim_set_decoration_provider: function(integer--[[Integer]], {string:any}--[[Dictionary]])--[[void]]
      nvim_set_hl: function(integer--[[Integer]], string--[[String]], {string:any}--[[Dictionary]])--[[void]]
      nvim_set_keymap: function(string--[[String]], string--[[String]], string--[[String]], {string:any}--[[Dictionary]])--[[void]]
      nvim_set_option: function(string--[[String]], any--[[Object]])--[[void]]
      nvim_set_option_value: function(string--[[String]], any--[[Object]], {string:any}--[[Dictionary]])--[[void]]
      nvim_set_var: function(string--[[String]], any--[[Object]])--[[void]]
      nvim_set_vvar: function(string--[[String]], any--[[Object]])--[[void]]
      nvim_strwidth: function(string--[[String]]): integer--[[Integer]]
      nvim_subscribe: function(string--[[String]])--[[void]]
      nvim_tabpage_del_var: function(integer--[[Tabpage]], string--[[String]])--[[void]]
      nvim_tabpage_get_number: function(integer--[[Tabpage]]): integer--[[Integer]]
      nvim_tabpage_get_var: function(integer--[[Tabpage]], string--[[String]]): any--[[Object]]
      nvim_tabpage_get_win: function(integer--[[Tabpage]]): integer--[[Window]]
      nvim_tabpage_is_valid: function(integer--[[Tabpage]]): boolean--[[Boolean]]
      nvim_tabpage_list_wins: function(integer--[[Tabpage]]): {integer}--[[ArrayOf(Window)]]
      nvim_tabpage_set_var: function(integer--[[Tabpage]], string--[[String]], any--[[Object]])--[[void]]
      nvim_ui_attach: function(integer--[[Integer]], integer--[[Integer]], {string:any}--[[Dictionary]])--[[void]]
      nvim_ui_detach: function()--[[void]]
      nvim_ui_pum_set_bounds: function(number--[[Float]], number--[[Float]], number--[[Float]], number--[[Float]])--[[void]]
      nvim_ui_pum_set_height: function(integer--[[Integer]])--[[void]]
      nvim_ui_set_option: function(string--[[String]], any--[[Object]])--[[void]]
      nvim_ui_try_resize: function(integer--[[Integer]], integer--[[Integer]])--[[void]]
      nvim_ui_try_resize_grid: function(integer--[[Integer]], integer--[[Integer]], integer--[[Integer]])--[[void]]
      nvim_unsubscribe: function(string--[[String]])--[[void]]
      nvim_win_call: function(integer--[[Window]], any--[[LuaRef]]): any--[[Object]]
      nvim_win_close: function(integer--[[Window]], boolean--[[Boolean]])--[[void]]
      nvim_win_del_var: function(integer--[[Window]], string--[[String]])--[[void]]
      nvim_win_get_buf: function(integer--[[Window]]): integer--[[Buffer]]
      nvim_win_get_config: function(integer--[[Window]]): {string:any}--[[Dictionary]]
      nvim_win_get_cursor: function(integer--[[Window]]): {integer,integer}--[[ArrayOf(Integer, 2)]]
      nvim_win_get_height: function(integer--[[Window]]): integer--[[Integer]]
      nvim_win_get_number: function(integer--[[Window]]): integer--[[Integer]]
      nvim_win_get_option: function(integer--[[Window]], string--[[String]]): any--[[Object]]
      nvim_win_get_position: function(integer--[[Window]]): {integer,integer}--[[ArrayOf(Integer, 2)]]
      nvim_win_get_tabpage: function(integer--[[Window]]): integer--[[Tabpage]]
      nvim_win_get_var: function(integer--[[Window]], string--[[String]]): any--[[Object]]
      nvim_win_get_width: function(integer--[[Window]]): integer--[[Integer]]
      nvim_win_hide: function(integer--[[Window]])--[[void]]
      nvim_win_is_valid: function(integer--[[Window]]): boolean--[[Boolean]]
      nvim_win_set_buf: function(integer--[[Window]], integer--[[Buffer]])--[[void]]
      nvim_win_set_config: function(integer--[[Window]], {string:any}--[[Dictionary]])--[[void]]
      nvim_win_set_cursor: function(integer--[[Window]], {integer,integer}--[[ArrayOf(Integer, 2)]])--[[void]]
      nvim_win_set_height: function(integer--[[Window]], integer--[[Integer]])--[[void]]
      nvim_win_set_option: function(integer--[[Window]], string--[[String]], any--[[Object]])--[[void]]
      nvim_win_set_var: function(integer--[[Window]], string--[[String]], any--[[Object]])--[[void]]
      nvim_win_set_width: function(integer--[[Window]], integer--[[Integer]])--[[void]]
   end


   record json
      record DecodeOpts
         record Luanil
            object: boolean
            array: boolean
         end

         luanil: Luanil
      end

      encode: function(string)
      decode: function(string, DecodeOpts)
   end

   record ui
      record InputOpts
         prompt: string
         completion: string
         highlight: function()
      end
      input: function(InputOpts, function(string))

      record SelectOpts
         prompt: string
         format_item: function(any): string
         kind: string
      end
      select: function(any, SelectOpts, function(any, integer))
   end
end
