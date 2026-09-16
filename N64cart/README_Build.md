# README_Build

Compilation du firmware **N64cart** pour une cartouche v3 (PCB SOIC-16, flash MX66L1G45G 128 Mo), sous Windows et sans WSL.

Sources : [github.com/pdaXrom/n64cart](https://github.com/pdaXrom/n64cart)

---

## 1. Configuration matérielle

| Élément | Valeur |
|---|---|
| Carte | v3 (`-DBOARD=v3`) |
| Puce flash | MX66L1G45G, 128 Mo |
| Console | PAL (`-DREGION=pal`) |
| Boot stage 2 | `board/boot2_mx66l.S`, sélectionné automatiquement par `BOARD=v3` |
| Offset ROMFS | `0x00010000` |

`REGION` ne détermine que le protocole CIC échangé avec la console. Il n'a aucun effet sur l'USB : une cartouche en firmware NTSC reste pilotable depuis le PC tout en donnant un écran noir sur une console PAL.

---

## 2. Prérequis

### Git pour Windows

Nécessaire à deux titres : l'extension VS Code s'en sert pour récupérer le SDK, et le `CMakeLists.txt` du projet appelle `git log -1 --format=%h` pour embarquer le hash de version dans le binaire.

Installation depuis [git-scm.com](https://git-scm.com), en cochant **« Git from the command line and also from 3rd-party software »**. Vérification dans un terminal neuf :

```powershell
git --version
```

Son absence n'est pas bloquante pour la compilation elle-même, le hash sera simplement vide.

### Toolchain Arm et SDK Pico

L'ancien installeur `pico-setup-windows` est archivé depuis fin 2024. La méthode officielle est désormais l'extension **Raspberry Pi Pico** pour Visual Studio Code.

1. Installer [Visual Studio Code](https://code.visualstudio.com)
2. `Ctrl+Shift+X`, chercher « Raspberry Pi Pico », éditeur **Raspberry Pi**, installer
3. Ouvrir l'icône Raspberry Pi dans la barre latérale, choisir **New C/C++ Project**, nom quelconque, options par défaut

> **L'installation de l'extension ne télécharge rien.** C'est la création du projet qui déclenche le téléchargement du SDK, du toolchain Arm, de CMake, de Ninja et de picotool dans `%USERPROFILE%\.pico-sdk`. Compter plusieurs minutes et quelques centaines de mégaoctets.

Vérification :

```powershell
Get-ChildItem $env:USERPROFILE\.pico-sdk
```

Les sous-dossiers `sdk`, `toolchain`, `cmake`, `ninja` et `picotool` doivent être présents.

> **Cursor et autres forks de VS Code** : l'extension Pico dépend de l'extension C/C++ de Microsoft, dont la licence la limite au VS Code officiel. Sur un fork, l'extension s'installe mais ne s'active pas complètement et la création de projet ne se déclenche jamais. Installer le vrai VS Code à côté pour cette étape, puis l'oublier : seul le dossier `.pico-sdk` compte ensuite.

Aucun compilateur natif (MinGW, Visual Studio Build Tools) n'est nécessaire : `picotool` et `pioasm` sont fournis précompilés.

---

## 3. Compilation avec le script

Placer `build-n64cart.ps1` à la racine du projet, à côté du dossier `fw`.

```powershell
cd C:\Users\<user>\Documents\N64\N64cart
powershell -ExecutionPolicy Bypass -File .\build-n64cart.ps1
```

Valeurs par défaut : **v3 / PAL**.

### Options

| Commande | Effet |
|---|---|
| `-Region ntsc` | build NTSC |
| `-Board v2` \| `pico` \| `pico-lite` | autre variante de carte |
| `-Clean` | supprime le dossier de build avant de recompiler |
| `-SdkVersion 2.1.1` | force une version d'outil au lieu de la plus récente |
| `-ProjectRoot <chemin>` | racine du projet si le script est ailleurs |

Les dossiers de build sont séparés par configuration (`fw\build-v3-pal`, `fw\build-v3-ntsc`), on peut donc alterner sans reconfigurer.

### Ce que fait le script

- détecte automatiquement les versions installées sous `%USERPROFILE%\.pico-sdk`
- refuse de démarrer si le chemin du projet contient un espace
- insère dans `fw\CMakeLists.txt` le bloc `pico-vscode.cmake` qui renseigne `PICO_SDK_PATH`, `PICO_TOOLCHAIN_PATH`, `picotool_DIR` et `pioasm_DIR` (sauvegarde en `.bak`, opération idempotente via un marqueur)
- configure avec Ninja, compile
- contrôle la taille du binaire et l'offset ROMFS résultant
- copie le résultat dans `Output\n64cart-<board>-<region>.uf2`

---

## 4. Contrainte critique : la taille du binaire

Le ROMFS ne commence pas à une adresse fixe. Le firmware la calcule à l'exécution :

```
offset ROMFS = align(taille_du_binaire, 32 Ko)
```

Tant que le binaire reste **sous 64 Ko**, l'offset vaut `0x00010000` et le catalogue de la cartouche reste lisible. Au-delà, il passerait à `0x00018000` : tous les fichiers deviendraient introuvables et il faudrait reformater puis recharger toutes les ROMs.

Tailles constatées pour la 1.13 en v3 :

| Toolchain | Taille du binaire | Offset ROMFS |
|---|---|---|
| Arm GCC 13.2 (Linux) | 42 556 o (NTSC) / 42 664 o (PAL) | `0x00010000` |
| Toolchain de l'extension (Windows) | 39 352 o (PAL) | `0x00010000` |

Le script affiche ce contrôle en fin de compilation et avertit en jaune si l'offset change.

Corollaire utile : le flashage UF2 ne réécrit que les premiers 64 Ko de la puce. **Mettre à jour le firmware ne touche pas aux ROMs stockées**, tant que l'offset reste identique.

---

## 5. Flashage

La carte n'expose pas de bouton BOOTSEL utilisable. Le passage en mode bootloader se fait par logiciel, via une commande USB que le firmware implémente depuis la version 1.11 :

- **ROM FS Manager** : menu `File` → `Bootloader`, puis confirmer
- **Ligne de commande** : `usb-romfs.exe bootloader`

La cartouche disparaît alors de ROM FS Manager (c'est attendu) et Windows monte le lecteur **RPI-RP2**. Glisser le `.uf2` dessus ; le lecteur se démonte tout seul en fin de copie, signe que le flashage a réussi.

Vérification ensuite dans ROM FS Manager : version affichée et `ROMFS start offset` à `00010000`.

Si `RPI-RP2` n'apparaît pas, débrancher et rebrancher : la carte repart sur l'ancien firmware, le boot ROM n'écrit rien tant qu'aucun fichier n'est copié.

> Il n'est **pas** possible de pousser un `.uf2` via ROM FS Manager. L'entrée `firmware` du ROMFS est marquée lecture seule et système, toute écriture est refusée. ROM FS Manager ne fait que passer la main au boot ROM du RP2040.

---

## 6. Compilation manuelle, sans le script

Ajouter en tête de `fw\CMakeLists.txt`, juste après `cmake_minimum_required` et **avant** `include(pico_sdk_import.cmake)` :

```cmake
set(USERHOME $ENV{USERPROFILE})
set(sdkVersion 2.1.1)
set(toolchainVersion 13_3_Rel1)
set(picotoolVersion 2.1.1)
set(picoVscode ${USERHOME}/.pico-sdk/cmake/pico-vscode.cmake)
if (EXISTS ${picoVscode})
    include(${picoVscode})
endif()
```

Les numéros de version doivent correspondre aux dossiers réellement présents sous `%USERPROFILE%\.pico-sdk`.

Puis, en ajoutant `toolchain\<ver>\bin`, `ninja\<ver>` et `cmake\<ver>\bin` au `PATH` de la session :

```powershell
cd fw
mkdir build
cd build
cmake -G Ninja -DBOARD=v3 -DREGION=pal ..
ninja
```

Le résultat est `fw\build\n64cart.uf2`.

En ouvrant simplement le dossier `fw` dans VS Code, l'extension configure et compile en un clic, mais **sans passer `REGION`** : la valeur par défaut est alors `ntsc`. Pour éviter le piège, remplacer `set(REGION "ntsc")` par `set(REGION "pal")` dans le `CMakeLists.txt`.

---

## 7. Alternative : WSL2

Si l'écosystème Windows pose problème, WSL2 reproduit à l'identique la chaîne Linux :

```bash
sudo apt update
sudo apt install -y cmake build-essential git python3 \
  gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib

git clone -b 2.1.1 --recurse-submodules https://github.com/raspberrypi/pico-sdk.git
git clone https://github.com/pdaXrom/n64cart.git
cd n64cart/fw && mkdir -p build && cd build
PICO_SDK_PATH=~/pico-sdk cmake -DBOARD=v3 -DREGION=pal ..
make -j$(nproc)
```

`libstdc++-arm-none-eabi-newlib` n'est pas optionnel : le SDK compile un fichier C++ et le build échoue sans lui.

Récupération du fichier côté Windows : `explorer.exe .` depuis le dossier `build`. L'absence d'accès USB sous WSL est sans conséquence, le flashage se fait depuis Windows.

---

## 8. Dépannage

| Symptôme | Cause et remède |
|---|---|
| `.pico-sdk est introuvable` | L'extension a été installée mais aucun projet créé. Créer un projet d'exemple dans VS Code. |
| Le panneau Pico ne répond pas | Fork de VS Code (Cursor, VSCodium). Utiliser le VS Code officiel pour cette étape. |
| `Le chemin contient un espace` | Le SDK Pico échoue de façon obscure sur les chemins avec espaces. Déplacer le projet. |
| Le script ne se lance pas | Stratégie d'exécution PowerShell. Utiliser `powershell -ExecutionPolicy Bypass -File .\build-n64cart.ps1`. |
| Le téléchargement du SDK échoue | Limite de requêtes GitHub. Renseigner un jeton dans le paramètre `raspberry-pi-pico.githubToken` (portée `public_repo`). |
| `Region NTSC` dans la sortie CMake | Le dossier de build a gardé l'ancienne configuration. Relancer avec `-Clean`. |
| Écran noir sur la console | Si le ROMFS ne contient pas `n64cart-manager.z64`, le firmware boucle avant de lancer le bus PI et le CIC. L'USB reste actif car il démarre plus tôt. |

---

## 9. Annexe : structure du ROMFS

Trois pseudo-entrées en lecture seule décrivent la flash elle-même :

| Entrée | Rôle | Emplacement |
|---|---|---|
| `firmware` | le binaire RP2040 en cours d'exécution | secteurs 0–15 (64 Ko) |
| `flashlist` | catalogue, entrées de 64 octets | secteurs 16–17 (8 Ko, 128 entrées max) |
| `flashmap` | chaînage des secteurs, 32768 × `uint16` | secteurs 18–33 (64 Ko) |

Format d'une entrée de `flashlist` (64 octets, little-endian) :

```
char     name[54]
uint16   attr     // mode:3, type:5, parent:4, current:4
uint32   start    // secteur de départ
uint32   size     // taille en octets
```

Types : `0` firmware, `1` flashlist, `2` flashmap, `3` répertoire, `0x1f` fichier.

Au démarrage, le firmware ouvre `n64cart-manager.z64` **par son nom** pour construire la table d'adresses présentée à la console. Sans ce fichier, la cartouche ne démarre pas.

### Commandes `usb-romfs.exe`

```
help
list [-h] [chemin]
free
push [--fix-rom] [--fix-pi-bus-speed[=12..FF]] <fichier local> [<chemin distant>]
pull <chemin distant> [<fichier local>]
delete <chemin>
rename <source> <destination> [--create-dirs]
mkdir <chemin>
rmdir <chemin>
format
reboot
bootloader
```

`remote-romfs.exe <ip du proxy> <commande...>` accepte la même syntaxe.

> `format` efface tout le catalogue et ne demande **aucune confirmation**. La commande est silencieuse en cas de succès comme d'échec, seules les trois lignes d'en-tête s'affichent. Elle ne réécrit que les secteurs 16 à 33 : les données des fichiers restent physiquement en flash, ce qui rend une récupération possible tant qu'aucune écriture ultérieure n'a réalloué les secteurs concernés.

**Sauvegarder `flashlist` et `flashmap` avant toute opération risquée** : ces deux fichiers suffisent à reconstruire l'index complet de la cartouche.
