<div align="center">

# Полноэкранные шейдеры для Hyprland

**Стопка эффектов и софтверная яркость** 　٩(◕‿◕)۶

![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=flat&logo=hyprland&logoColor=black)
![GLSL](https://img.shields.io/badge/GLSL-ES_3.0-5586A4?style=flat&logo=opengl&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/hyprland-screen-shader/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/hyprland-screen-shader/actions/workflows/build.yml)

[English](README.md)

</div>

У Hyprland ровно **один** слот шейдера — `decoration:screen_shader`. Из-за этого ночной тёплый фильтр, затемнение и кинескоп взаимно исключают друг друга: выигрывает тот, кого выставили последним, остальные просто пропадают. Менеджер забирает слот себе и **композирует**: каждый эффект — это один файл с единственной функцией `vec3 effect(vec3 c, vec2 uv)`, а из активных плюс множителя яркости собирается один сгенерированный шейдер

Яркость тоже софтверная: на десктопе подсветку крутить нечем, поэтому затемнение — это умножение цвета. Заодно оно уходит ниже "железного" минимума и поднимается выше 100%

Перекочевало из моего райса **[rokokol/huix](https://github.com/rokokol/huix)**

```sh
# примерить на живой сессии, ничего не устанавливая
nix run github:rokokol/hyprland-screen-shader -- flash crt 3
```

## Эффекты

| | | |
| --- | --- | --- |
| ⚫ `grayscale` | 🟤 `sepia` | 🔄 `invert` |
| 🌅 `warm` — режет синий, на вечер | ❄️ `cool` | 🎯 `vignette` |
| 🔪 `sharpen` — ядро 3×3 | 🎨 `posterize` | 🌈 `none` — только затемнение |
| 📺 `crt` — кривизна, теневая маска, скан-линии | 🟢 `matrix` — цифровой дождь | 💾 `jpeg` — блочность DCT и звон |
| 🌊 `wave` — медленная рябь | 📡 `glitch` — RGB-split и рвущиеся строки | |

Они **стакаются**. `effect push` кладёт фильтр поверх текущих, `effect toggle` добавляет или убирает, `effect clear` сбрасывает всё. Эффекты, которые сэмплят текстуру со смещением (`crt`, `wave`, `glitch`, `jpeg`, `sharpen`), идут в цепочке первыми, цветовые — после: сначала геометрия, потом покраска результата. Два геометрических честно в один проход не сложить, поэтому последний перекрывает предыдущий

## Установка

### Home Manager

```nix
{
  inputs.screen-shader.url = "github:rokokol/hyprland-screen-shader";

  # в домашней конфигурации
  imports = [ inputs.screen-shader.homeManagerModules.default ];

  programs.screen-shader = {
    enable = true;
    waybar = {
      signal = 8;
      bars = [ "mainBar" ];
    };
  };
}
```

Это вся настройка. Включение ставит пакет, вешает бинды, объявляет пикер как rofi-modi (со своим эмодзи режима) и определяет модуль `custom/shader` в перечисленных барах. Остаётся только решить, *где* в баре стоять индикатору — добавить `"custom/shader"` в `modules-right` (или left, или center; вот это угадать невозможно)

| Клавиши | Действие |
| --- | --- |
| `SUPER SHIFT + G` | пикер: все эффекты плюс кнопки яркости |
| `SUPER + G` | сбросить стопку |
| `SUPER CTRL + ]` / `[` | яркость ±5%, повторяется при удержании |
| `SUPER CTRL + Backspace` | яркость обратно в 100% |

Меняется через `hyprland.modifier`, либо заменой всего `hyprland.settings`, либо `{ }` — и вешаешь бинды сам

### Любой другой дистрибутив

```sh
git clone https://github.com/rokokol/hyprland-screen-shader
cd hyprland-screen-shader
sudo ./install.sh          # PREFIX=~/.local ./install.sh — поставить в пользователя
```

Собирать нечего: скрипты и эффекты копируются в `$PREFIX/share/screen-shader` и линкуются в `$PREFIX/bin`. Свою директорию скрипты вычисляют сами, разрешая симлинк, так что путь к эффектам нигде не прописывается

Нужны `bash`, `awk`, `sed`, `grep`, `flock`, `hyprctl` и — для пикера — `rofi`. `notify-send` необязателен: без него сообщения идут в stderr

Бинды в этом случае свои:

```conf
bind  = SUPER SHIFT, G, exec, rofi-shader
bind  = SUPER, G, exec, screen-shader effect clear
bindel = SUPER CTRL, bracketright, exec, screen-shader bright up
bindel = SUPER CTRL, bracketleft, exec, screen-shader bright down
bind  = SUPER CTRL, BackSpace, exec, screen-shader bright reset
exec  = screen-shader restore
```

Именно `exec`, а не `exec-once`: слот шейдера — рантайм-состояние, его надо применять заново на каждый reload

## Команды

```sh
screen-shader effect push|set|toggle|clear|next|prev <имя>
screen-shader bright up|down|reset|toggle|set <0.10..2.00>|get
screen-shader flash [-k] <имя> [секунды]    # поверх стопки, durable state не трогает
screen-shader restore                       # применить сохранённый выбор
screen-shader reset-all                     # эффекты и яркость одним движением
screen-shader status                        # JSON для waybar-модуля
screen-shader menu                          # "<эмодзи> <подпись>|<имя>" для пикера
```

`flash` сделан для вызова снаружи: подмешивает эффект поверх текущего на секунду-другую и возвращает как было, не трогая durable-состояние. С `-k` он молча ничего не делает, если стопка занята, — чтобы не спорить с осознанным выбором

Выбор (стопка и яркость) лежит в `$XDG_STATE_HOME/screen-shader/state` и переживает перезагрузку. Сгенерированные шейдеры эфемерны, в `$XDG_RUNTIME_DIR/screen-shader`

## Как добавить эффект

Положить один файл в директорию шейдеров. Больше ничего: ни списка, куда дописать имя, ни таблицы, которую надо держать в синхроне:

```glsl
// label: Bloom
// emoji: 🔆
// order: 65

vec3 effect(vec3 c, vec2 uv) {
    vec3 blur = texture(tex, uv + vec2(0.002)).rgb;
    return max(c, blur * 0.8);
}
```

`c` — цвет пикселя на текущий момент, `uv` бежит 0..1, доступны `tex`, `time` (секунды) и `BRIGHTNESS`. `#version`, `main` и объявления юниформов писать не надо — их добавит менеджер. Имена хелперов могут совпадать между эффектами: при композиции менеджер сам навешивает суффиксы на последующие тела (`hash` → `hash_1`)

Заголовок — весь контракт эффекта с пикером: `label` и `emoji` видно в меню, `order` задаёт место в нём и в `next`/`prev`

**Режим отрисовки нигде не объявляется — он читается из кода.** Используешь `time` — эффект анимированный; зовёшь `texture()` — искажаешь геометрию. Менеджер сам выставляет damage tracking:

| | когда | `damage_tracking` / `vfr` | почему |
| --- | --- | --- | --- |
| анимация | в теле есть `time` | `0` / `0` | нужен кадр на каждый тик; при VFR Hyprland уходит в idle и анимация дёргается |
| смещение | в теле есть `texture()` | `1` / `1` | смещённая выборка читает соседние области, которые точный damage ещё не отрисовал — перерисовываем весь монитор, но в простое спим |
| обычный | ни того, ни другого | `2` / `1` | попиксельный эффект, частичный damage ок |

Перед этой проверкой комментарии вырезаются, так что фраза про `time` в прозе не сделает статический эффект анимированным

На Home Manager ради одного эффекта форкать репозиторий не нужно:

```nix
programs.screen-shader.extraShaders.bloom = ./bloom.frag;
```

## Waybar

`waybar.bars` определяет модуль, место выбираешь сам:

```nix
programs.waybar.settings.mainBar.modules-right = [ "custom/shader" "clock" ];
```

ЛКМ — пикер, ПКМ — полный сброс, СКМ — яркость пополам, колесо — яркость. Модуль прячется, когда эффектов нет и яркость 100%

Индикатор обновляется по `SIGRTMIN+N`, где `N` берётся из `waybar.signal` — объявляется один раз и запекается в пакет, поэтому скрипт и бар не могут разойтись в номере. **Дефолтное действие RT-сигнала — завершить процесс**, поэтому слать его до того, как waybar поставил обработчик, нельзя; `screen-shader restore` именно поэтому не шлёт ничего, а на старте сигнал и не нужен — waybar сам читает `status`

## Тесты

```sh
tests/run.sh              # 69 проверок, композитор не нужен
tests/run.sh --update     # перезаписать эталонные шейдеры после осознанного изменения
```

`hyprctl` и `notify-send` подменены заглушками, состояние уходит во временную директорию, а сгенерированный GLSL сравнивается с закоммиченными эталонами — так изменение в сборке шейдеров всплывает диффом, а не сюрпризом при следующем логине. `nix flake check` гоняет сьют плюс: каждый эффект отдельно и все разом через `glslangValidator`, наличие заголовков `// label:`, обёртки пакета и модуль Home Manager, вычисленный против заглушек опций

## Что где

```
screen-shader.sh   менеджер: состояние, сборка шейдера, режимы отрисовки, индикатор
rofi-shader.sh     пикер, rofi script-modi, который сам себя и запускает
shaders/*.frag     один эффект — один файл
nix/               package.nix, module.nix, module-test.nix
tests/             run.sh и эталонные шейдеры
```

## Лицензия

MIT
