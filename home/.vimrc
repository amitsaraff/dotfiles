" ==============================================================================
" .vimrc
" ==============================================================================

set nocompatible
filetype plugin indent on

" UI / display
syntax on
set number
set ruler
set laststatus=2
set showmode
set showcmd
set scrolloff=3
set ttyfast
set foldcolumn=1
set t_Co=256
set noerrorbells
set novisualbell
set t_vb=
set tm=500

" Encoding and whitespace
set encoding=utf-8
set wrap
set textwidth=79
set formatoptions=tcqrn1
set tabstop=4
set shiftwidth=4
set softtabstop=4
set expandtab
set noshiftround
set listchars=tab:▸\ ,eol:¬
map <leader>l :set list!<CR>

" Navigation and motion
set backspace=indent,eol,start
set matchpairs+=<:>
runtime! macros/matchit.vim
nnoremap j gj
nnoremap k gk
set hidden

" Search
set hlsearch
set incsearch
set ignorecase
set smartcase
set showmatch
nnoremap / /\v
vnoremap / /\v
map <leader><space> :let @/=''<CR>

" Key mappings
inoremap <F1> <ESC>:set invfullscreen<CR>a
nnoremap <F1> :set invfullscreen<CR>
vnoremap <F1> :set invfullscreen<CR>
map <leader>q gqip

" Colours and files
set background=dark
set nobackup
set nowritebackup
set noswapfile
set modelines=0
