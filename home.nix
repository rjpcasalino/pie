{ pkgs, ... }:

{
  home.username = "rjpc";
  home.homeDirectory = "/home/rjpc";
  home.packages = with pkgs; [
    bc
    curl
    direnv
    du-dust
    ed
    fd
    feh
    fortune
    go
    gopls
    nixpkgs-fmt
    osv-scanner
    rnix-lsp # nix lang server
    unzip
    wget
  ];

  home.stateVersion = "22.05";

  home.sessionVariables = {
    EDITOR = "vim";
  };

  programs.home-manager.enable = true;

  programs.chromium.enable = false;

  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    enableCompletion = true;
    shellAliases = {
      ll = "ls -l";
      ".." = "cd ..";
      "..." = "cd ../..";
      "dc" = "docker-compose";
      "de" = "docker exec -it";
      "dps" = "docker ps";
      "dnls" = "docker network ls";
      "dnin" = "docker network inspect";
      "ddie" = "docker system prune -a --volumes";
      "fd" = "fd -c never"; # never use color output on fd
      "nd" = "nix develop";
      "g" = "git";
      "zits" = "sudo nixos-rebuild switch --flake .#zits";
    };
    initExtra = ''
      export GIT_PS1_SHOWDIRTYSTATE=1
      export GIT_PS1_SHOWSTASHSTATE=1
      export GIT_PS1_SHOWCOLORHINTS=1
      export GIT_PS1_SHOWUPSTREAM="auto"
      setopt PROMPT_SUBST
      autoload -U colors && colors
      eval "$(direnv hook zsh)"
      bindkey -e
      if [[ "$SSH_TTY" ]]; then
        export PS1='%F{#C600E8}SSH on %m%f %F{magenta}%n%f %B%F{red}%~%f $(__git_ps1 "(%s) ")%b%# '
      else
        export PS1='%F{magenta}%n%f %B%F{blue}%~%f $(__git_ps1 "(%s) ")%b%# '
      fi;
    '';
  };

  programs.git = {
    enable = false;
    userName = "rjpc";
    userEmail = "rjpc@rjpc.net";
    aliases = {
      a = "add";
      c = "commit";
      d = "diff";
      f = "fetch";
      s = "status";
      l = "log --graph --decorate --pretty=oneline --abbrev-commit";
      pu = "push";
    };
  };

  programs.jq = {
    enable = true;
    colors = {
      null = "1;30";
      false = "0;31";
      true = "0;32";
      numbers = "0;36";
      strings = "0;33";
      arrays = "1;35";
      objects = "1;37";
    };
  };

  programs.ripgrep.enable = true;

  programs.vim = {
    enable = true;
    plugins =  builtins.attrValues {
      inherit (pkgs.vimPlugins)
      colorizer
      csv-vim
      csv
      lightline-vim
      matchit-zip
      vim-go
      vim-nix
      vim-terraform
      vim-lsp;
    };
    settings = {
      background = "light";
      mouse = "a";
      number = true;
      tabstop = 4;
    };
    extraConfig = ''
      if !has('gui_running')
        set t_Co=256
      endif
      colorscheme default
      syntax on
      set expandtab
      set tabstop=4
      set ruler
      set hlsearch
      set spelllang=en_us
      set paste
      set list
      set listchars=eol:¬,tab:▸\ ,trail:·
      set wildmenu
      set wildmode=longest,list,full
      " don't pollute dirs with swap files
      " keep them in one place
      silent !mkdir -p ~/.vim/{backup,swp}/
      set backupdir=~/.vim/backup/
      set directory=~/.vim/swp/
      let g:netrw_preview = 1
      let g:netrw_banner = 1
      let g:netrw_liststyle = 3
      let g:netrw_winsize = 25
      noremap <F11> :tabprevious<CR>
      noremap <F12> :tabnext<CR>
      augroup vimrc
        autocmd!
        au BufRead,BufNewFile *.md,*.txt,*.man,*.ms setlocal spell
        hi clear SpellBad
        hi SpellBad cterm=underline,bold ctermfg=red
      augroup END
      runtime macros/matchit.vim
    '';
  };
}
