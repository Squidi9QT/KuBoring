#!/bin/bash
# Двойной клик: ставит xcodegen (если нужно), генерирует проект и открывает его в Xcode.
cd "$(dirname "$0")" || exit 1

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Устанавливаю xcodegen через Homebrew..."
    brew install xcodegen || { echo "Не удалось установить xcodegen."; read -r -p "Нажмите Enter для выхода..."; exit 1; }
  else
    echo "Не найден Homebrew, а он нужен для установки xcodegen."
    echo "Установите Homebrew командой с сайта https://brew.sh :"
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo "Затем запустите setup.command ещё раз."
    read -r -p "Нажмите Enter для выхода..."
    exit 1
  fi
fi

echo "Генерирую KuBoring.xcodeproj..."
xcodegen generate || { echo "xcodegen завершился с ошибкой."; read -r -p "Нажмите Enter для выхода..."; exit 1; }

echo "Открываю проект в Xcode..."
open KuBoring.xcodeproj
