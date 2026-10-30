Beats Drum Machine
------------------

## Sequenciador no terminal (Windows)

Na pasta do projeto, instale as dependências com `bundle install` e inicie:

```powershell
bundle exec .\beats
bundle exec .\beats projeto_1.brf
```

Sem argumento, abre o projeto padrão definido em [beats.yml](beats.yml).
O nome é o próximo `projeto_N.brf` disponível. Com argumento, procura primeiro
o arquivo relativo ao diretório atual e depois na pasta `ProjectsPath`.
Também aceita um caminho absoluto. Para outra configuração:

```powershell
bundle exec .\beats --config C:\temp\beats.yml
```

Esta primeira versão edita um único padrão `Verse`, com 16 passos por pista
e `Flow` fixo em `Verse: x1`. O campo selecionado aparece em destaque.

| Tecla | Ação |
|---|---|
| Esquerda / direita | Mover entre passos; ao passar da borda, ir à próxima pista ou ao rodapé |
| Cima / baixo na grade | Selecionar outra pista; abaixo da última, selecionar Tempo |
| Tab num passo | Alternar entre som (`X`) e pausa (`=`) |
| Cima / baixo em Tempo | Aumentar / diminuir 1 BPM (1 a 999) |
| Esquerda em Tempo | Voltar ao último passo da grade |
| Direita em Tempo | Selecionar Sair, depois Gerar |
| Tab em Sair | Salvar o `.brf` e encerrar |
| Tab em Gerar | Gerar/sobrescrever o WAV com as alterações atuais e continuar editando |
| Ctrl+C | Salvar e encerrar, como Sair |

Use um terminal com suporte ANSI (como o terminal integrado do VSCode ou
Windows Terminal), com pelo menos 60 colunas e 12 linhas. Listas maiores de
pistas acompanham a seleção com rolagem. A geração é offline; não há reprodução
em tempo real nesta versão. Erros aparecem na tela. Se não conseguir salvar,
a aplicação permanece aberta com as alterações.

### Configuração e arquivos

Edite `beats.yml` para alterar:

- `Indicators.Active` / `Indicators.Rest`: caracteres usados na tela.
- `SamplesPath`: pasta dos samples WAV.
- `ProjectsPath`: pasta de novos projetos e busca de projetos pelo nome.
- `AudioPath`: pasta dos WAV gerados.
- `AudioFile`: opcional; nome fixo ou caminho completo do WAV. Com `null`,
  usa o nome do projeto, como `projeto_1.wav`.
- `PreserveTails`: `false` por padrão; termina o WAV no fim do `Flow`.
  Use `true` para deixar os últimos samples terminarem depois desse ponto.
- `TrimLeadingSilence`: `true` por padrão no editor; remove o trecho inicial
  abaixo de 1% do pico de cada sample para alinhar o ataque ao passo `X`.
  Não altera os WAV originais. Use `false` para preservar o início gravado.
- `Kit`: nomes dos instrumentos e arquivos de samples.
- `Default`: tempo e sequência inicial das pistas. Use `X` e `.` aqui.

Os caminhos relativos da configuração partem da pasta de `beats.yml`.
Para caminhos Windows absolutos, use aspas simples: `'C:\temp\samples'`.
O padrão usa cinco sons de `musik/samples`: bass, snare, hihat, openhat e ride.
Novos projetos são salvos em `musik/projects` e o áudio em `musik/output`.

Os arquivos `.brf` são YAML com `Song`, `Kit` e `Verse`, preservando o Kit e
o caminho dos samples de cada projeto. O caminho dos samples é relativo ao
arquivo `.brf` quando possível. Os passos são salvos como `X`/`.` para manter
compatibilidade com o motor de áudio; trocar os indicadores não altera o som.
O asterisco no título indica alterações ainda não salvas. Gerar não salva
o projeto; Sair salva. Arquivos existentes são substituídos somente depois
que a escrita termina com sucesso.

O comando original permanece disponível para gerar músicas YAML sem o editor:

```powershell
bundle exec ruby -Ilib bin/beats musik/example_song.yaml musik/output/example.wav
```

O áudio termina no fim da sequência do `Flow`, mesmo que um sample contenha
uma cauda longa ou silêncio no final. Sons podem continuar entre padrões;
o corte acontece somente no final da música. Por exemplo, a 120 BPM, dois
`Verse` e dois `Chorus` de 16 passos resultam em aproximadamente 8 segundos.
Para preservar as caudas na exportação por linha de comando, use
`--preserve-tails`. No editor, use `PreserveTails: true` em `beats.yml`.
Na linha de comando, `--trim-leading-silence` ativa o alinhamento dos ataques
também para músicas YAML. Sem essa opção, a linha de comando mantém o início
original dos samples.

Beats is a command-line drum machine written in pure Ruby. Feed it a song notated in YAML, and it will produce a precision-milled *.wav file of impeccable timing and feel. Here's an example song:

    Song:
      Tempo: 105
      Flow:
        - Verse:  x4
        - Chorus: x4
      Kit:
        - bass:     house_2_1.wav
        - snare:    roland_tr_909_2.wav
        - hihat:    house_2_5.wav
        - cowbell:  big_beat_5.wav
        - deep:     house_2_2.wav

    Verse:
      - bass:     X..X...X..X.....
      - snare:    ....X.......X...
      - hihat:    ..X...X...X...X.

    Chorus:
      - bass:     X..X...X..X.....
      - snare:    ....X.......X...
      - hihat:    XXXXXXXXXXXXX...
      - cowbell:  ....XX.X..X.X...
      - deep:     .............X..

And [here's what it sounds like](https://beatsdrummachine.com/media/beat.mp3) after getting the Beats treatment. What a glorious groove!

For more, check out [beatsdrummachine.com](https://beatsdrummachine.com)


Installation
------------

To install the latest stable version (2.1.2) from [rubygems.org](https://rubygems.org/gems/beats), run the following from the command line:

    gem install beats

Note: if you're installing using the default version of Ruby that comes with macOS, you might get a file permission error. If that happens, use `sudo gem install beats` instead. If you're using a version manager such as rbenv, chruby, or RVM, plain `gem install beats` should work fine.

Once installed, you can then run Beats from the command-line using the `beats` command.

Beats is not very useful unless you have some sounds to use with it. You can download some example sounds from [https://beatsdrummachine.com](https://beatsdrummachine.com/download#drum-kits).


Usage
-----

Beats runs from the command-line. Run `beats -h` to see the available options. For more detailed instructions, visit <https://beatsdrummachine.com/usage/>.

Check out [this tutorial at beatsdrummachine.com](https://beatsdrummachine.com/tutorial/) to see an example of how to create a beat from scratch.


What's New in v2.1.2
--------------------

The latest version of Beats is 2.1.2, released on December 18, 2019. It contains these changes:

* Several confusing/unhelpful errors shown due to an error in an input file have been improved. For example, if a pattern has the invalid name "4", the error message will now be `Pattern name '4' is not valid. It must be a value that will be parsed from YAML as a String.`, instead of `undefined method 'downcase' for 4:Integer`.

For info about previous releases, visit https://github.com/jstrait/beats/releases.


Local Development
-----------------

### VSCode on Windows

The workspace settings in `.vscode/settings.json` use RubyInstaller at
`C:/Ruby40-x64/bin/ruby.exe`. Custom Ruby LSP activation adds its `bin`
directory to the extension environment so that `ruby`, `gem`, and `bundle`
can all be found. The same directory is added to new integrated terminals.
Adjust these paths if Ruby is installed elsewhere.

When opening a `.code-workspace` file, set `rubyLsp.rubyVersionManager` to
`{ "identifier": "custom" }` in that file's `settings` as well. Set the
machine-scoped `rubyLsp.customRubyCommand` in VSCode User Settings to
`set "PATH=C:\Ruby40-x64\bin;%PATH%"` on Windows. Ruby LSP reads activation
settings at workspace level, so folder settings alone may not apply there.

After opening this folder, run **Developer: Reload Window** from the command
palette and open a new terminal. Ruby LSP prepares its tooling in `.ruby-lsp/`
on first use. Check `ruby -v` and `bundle -v` in the new terminal.

Use **Tasks: Run Task** to install dependencies or run the test suite with the
provided Ruby tasks. With Ruby 4, use Bundler 4.0.20 (as recorded in
`Gemfile.lock`); the original Bundler 1.17.3 is incompatible.

First, install the required dependencies:

    bundle install

To run Beats locally, use `bundle exec` and run `bin/beats`, to avoid using any installed gem executable. For example:

    bundle exec bin/beats -v

To run the tests:

    bundle exec rake test



Found a Bug? Have a Suggestion? Want to Contribute?
---------------------------------------------------

Contact me (Joel Strait) by opening a GitHub issue.


License
-------
Beats Drum Machine is released under the MIT license.
