
const TRANSLATIONS = {
  fr: {
    'status.connected': 'Cartouche connectée',
    'status.disconnected': 'Cartouche non connectée',
    'status.hint': 'Branchez la cartouche n64cart en USB puis cliquez sur Connecter.',
    'status.device': 'Firmware {version} · espace ROMFS {size} · offset 0x{offset}',

    'btn.connect': 'Connecter',
    'btn.disconnect': 'Déconnecter',
    'btn.up': 'Dossier parent',
    'btn.refresh': 'Rafraîchir',
    'btn.add': '+ Ajouter des jeux',
    'btn.newFolder': 'Nouveau dossier',
    'btn.system': 'Fichiers système',
    'btn.systemTitle': 'Afficher ou masquer le firmware et les fichiers système',
    'btn.download': 'Récupérer',
    'btn.rename': 'Renommer',
    'btn.delete': 'Supprimer',
    'btn.reboot': 'Redémarrer',
    'btn.firmware': 'Firmware…',
    'btn.firmwareTitle': 'Sélectionner un .uf2 : la cartouche se met à jour et redémarre',
    'btn.format': 'Formater',
    'btn.validate': 'Valider',
    'btn.cancel': 'Annuler',

    'path.root': 'Cartouche',
    'opt.fixRom': "Convertir les ROMs en .z64 à l'envoi",
    'col.name': 'Nom',
    'col.type': 'Type',
    'col.size': 'Taille',

    'type.folder': 'Dossier',
    'type.firmware': 'Firmware',
    'type.system': 'Système',
    'type.rom': 'Jeu N64',
    'type.file': 'Fichier',
    'badge.readonly': 'lecture seule',

    'list.empty': 'Dossier vide — glissez des fichiers .z64/.n64/.v64 ici.',
    'list.connectFirst': "Connectez la cartouche pour voir les jeux qu'elle contient.",
    'drop.hint': 'Déposez les ROMs pour les envoyer sur la cartouche',

    'statusbar.free': '{size} libres · {count} élément(s)',
    'statusbar.hidden': ' · {count} masqué(s)',

    'msg.connected': 'Cartouche connectée',
    'msg.disconnected': 'Cartouche déconnectée',
    'msg.folderCreated': 'Dossier {name} créé',
    'msg.renamed': 'Renommé en {name}',
    'msg.deleted': '{name} supprimé',
    'msg.formatted': 'Cartouche formatée',
    'msg.rebooted': 'Cartouche redémarrée',
    'msg.saved': 'Enregistré dans {path}',
    'msg.uploaded': '{count} fichier(s) envoyé(s)',
    'msg.firmwareOk': 'Firmware {name} installé, cartouche redémarrée',
    'msg.firmwareManual': 'Firmware {name} installé — rebranche la cartouche puis clique sur Connecter',

    'manager.missing': "Le menu n64cart-manager.z64 est absent de la cartouche.",
    'manager.add': 'Ajouter le menu',
    'manager.installed': 'Menu n64cart-manager.z64 ajouté',
    'op.installManager': 'Installation du menu',
    'dialog.managerTitle': 'Choisir n64cart-manager.z64',
    'theme.button': 'Thème',
    'theme.title': 'Habillage',
    'theme.threatrix': 'Threatrix',
    'theme.cyber': 'Cyber',
    'theme.colorTitle': 'Couleur',
    'color.blue': 'Bleu',
    'color.cyan': 'Cyan',
    'color.teal': 'Turquoise',
    'color.green': 'Vert',
    'color.lime': 'Vert citron',
    'color.yellow': 'Jaune',
    'color.orange': 'Orange',
    'color.red': 'Rouge',
    'color.pink': 'Rose',
    'color.purple': 'Violet',
    'color.indigo': 'Indigo',
    'prompt.newFolder': 'Nom du nouveau dossier',
    'prompt.newName': 'Nouveau nom',

    'confirm.deleteTitle': 'Supprimer',
    'confirm.deleteMessage': 'Supprimer {name} ?',
    'confirm.deleteFileDetail': 'Le fichier sera effacé de la cartouche. Cette action est définitive.',
    'confirm.deleteDirDetail': 'Le dossier doit être vide. Cette action est définitive.',
    'confirm.formatTitle': 'Formater la cartouche',
    'confirm.formatMessage': 'Formater tout le stockage de la cartouche ?',
    'confirm.formatDetail': 'Tous les jeux et dossiers seront effacés. Cette action est définitive.',

    'overlay.working': 'Opération en cours',

    'unit.b': 'o',
    'unit.kb': 'Kio',
    'unit.mb': 'Mio',
    'unit.gb': 'Gio',

    'dialog.pickRoms': 'Ajouter des jeux',
    'dialog.romFilter': 'ROMs N64',
    'dialog.allFilter': 'Tous les fichiers',
    'dialog.saveTitle': 'Enregistrer le jeu',
    'dialog.firmwareTitle': 'Choisir le firmware à installer',
    'dialog.firmwareFilter': 'Firmware RP2040',

    'op.connect': 'Connexion',
    'op.disconnect': 'Déconnexion',
    'op.list': 'Lecture',
    'op.mkdir': 'Création du dossier',
    'op.delete': 'Suppression',
    'op.rename': 'Renommage',
    'op.format': 'Formatage',
    'op.reboot': 'Redémarrage',
    'op.upload': 'Envoi',
    'op.download': 'Récupération',
    'op.firmware': 'Mise à jour du firmware',
    'op.uploading': 'Envoi de {name}',
    'op.downloading': 'Récupération de {name}',

    'fw.bootloader': 'Passage de la cartouche en mode bootloader',
    'fw.wait': 'Attente du lecteur RPI-RP2',
    'fw.copy': 'Copie de {name}',
    'fw.reboot': 'Redémarrage de la cartouche',

    'err.invalidName': 'Nom invalide : {name}',
    'err.nameTooLong': 'Nom trop long ({max} caractères maximum) : {name}',
    'err.notUf2': "{name} n'est pas un fichier .uf2 valide.",
    'err.noDrive':
      "Le lecteur RPI-RP2 n'est pas apparu. Débranche puis rebranche la cartouche en maintenant BOOTSEL, puis réessaie."
  },

  en: {
    'status.connected': 'Cart connected',
    'status.disconnected': 'Cart not connected',
    'status.hint': 'Plug the n64cart in over USB, then click Connect.',
    'status.device': 'Firmware {version} · ROMFS space {size} · offset 0x{offset}',

    'btn.connect': 'Connect',
    'btn.disconnect': 'Disconnect',
    'btn.up': 'Parent folder',
    'btn.refresh': 'Refresh',
    'btn.add': '+ Add games',
    'btn.newFolder': 'New folder',
    'btn.system': 'System files',
    'btn.systemTitle': 'Show or hide the firmware and system files',
    'btn.download': 'Download',
    'btn.rename': 'Rename',
    'btn.delete': 'Delete',
    'btn.reboot': 'Reboot',
    'btn.firmware': 'Firmware…',
    'btn.firmwareTitle': 'Pick a .uf2: the cart updates itself and reboots',
    'btn.format': 'Format',
    'btn.validate': 'OK',
    'btn.cancel': 'Cancel',

    'path.root': 'Cart',
    'opt.fixRom': 'Convert ROMs to .z64 when sending',
    'col.name': 'Name',
    'col.type': 'Type',
    'col.size': 'Size',

    'type.folder': 'Folder',
    'type.firmware': 'Firmware',
    'type.system': 'System',
    'type.rom': 'N64 game',
    'type.file': 'File',
    'badge.readonly': 'read-only',

    'list.empty': 'Empty folder — drop .z64/.n64/.v64 files here.',
    'list.connectFirst': 'Connect the cart to see the games it holds.',
    'drop.hint': 'Drop ROMs to send them to the cart',

    'statusbar.free': '{size} free · {count} item(s)',
    'statusbar.hidden': ' · {count} hidden',

    'msg.connected': 'Cart connected',
    'msg.disconnected': 'Cart disconnected',
    'msg.folderCreated': 'Folder {name} created',
    'msg.renamed': 'Renamed to {name}',
    'msg.deleted': '{name} deleted',
    'msg.formatted': 'Cart formatted',
    'msg.rebooted': 'Cart rebooted',
    'msg.saved': 'Saved to {path}',
    'msg.uploaded': '{count} file(s) sent',
    'msg.firmwareOk': 'Firmware {name} installed, cart rebooted',
    'msg.firmwareManual': 'Firmware {name} installed — replug the cart, then click Connect',

    'manager.missing': 'The n64cart-manager.z64 menu is missing from the cart.',
    'manager.add': 'Add the menu',
    'manager.installed': 'n64cart-manager.z64 menu added',
    'op.installManager': 'Installing the menu',
    'dialog.managerTitle': 'Choose n64cart-manager.z64',
    'theme.button': 'Theme',
    'theme.title': 'Skin',
    'theme.threatrix': 'Threatrix',
    'theme.cyber': 'Cyber',
    'theme.colorTitle': 'Colour',
    'color.blue': 'Blue',
    'color.cyan': 'Cyan',
    'color.teal': 'Teal',
    'color.green': 'Green',
    'color.lime': 'Lime',
    'color.yellow': 'Yellow',
    'color.orange': 'Orange',
    'color.red': 'Red',
    'color.pink': 'Pink',
    'color.purple': 'Purple',
    'color.indigo': 'Indigo',
    'prompt.newFolder': 'New folder name',
    'prompt.newName': 'New name',

    'confirm.deleteTitle': 'Delete',
    'confirm.deleteMessage': 'Delete {name}?',
    'confirm.deleteFileDetail': 'The file will be erased from the cart. This cannot be undone.',
    'confirm.deleteDirDetail': 'The folder must be empty. This cannot be undone.',
    'confirm.formatTitle': 'Format the cart',
    'confirm.formatMessage': 'Format the whole cart storage?',
    'confirm.formatDetail': 'Every game and folder will be erased. This cannot be undone.',

    'overlay.working': 'Working',

    'unit.b': 'B',
    'unit.kb': 'KiB',
    'unit.mb': 'MiB',
    'unit.gb': 'GiB',

    'dialog.pickRoms': 'Add games',
    'dialog.romFilter': 'N64 ROMs',
    'dialog.allFilter': 'All files',
    'dialog.saveTitle': 'Save the game',
    'dialog.firmwareTitle': 'Choose the firmware to install',
    'dialog.firmwareFilter': 'RP2040 firmware',

    'op.connect': 'Connecting',
    'op.disconnect': 'Disconnecting',
    'op.list': 'Reading',
    'op.mkdir': 'Creating folder',
    'op.delete': 'Deleting',
    'op.rename': 'Renaming',
    'op.format': 'Formatting',
    'op.reboot': 'Rebooting',
    'op.upload': 'Sending',
    'op.download': 'Downloading',
    'op.firmware': 'Firmware update',
    'op.uploading': 'Sending {name}',
    'op.downloading': 'Downloading {name}',

    'fw.bootloader': 'Switching the cart to bootloader mode',
    'fw.wait': 'Waiting for the RPI-RP2 drive',
    'fw.copy': 'Copying {name}',
    'fw.reboot': 'Rebooting the cart',

    'err.invalidName': 'Invalid name: {name}',
    'err.nameTooLong': 'Name too long ({max} characters max): {name}',
    'err.notUf2': '{name} is not a valid .uf2 file.',
    'err.noDrive':
      'The RPI-RP2 drive did not show up. Unplug the cart, plug it back while holding BOOTSEL, then try again.'
  }
};

const DEFAULT_LANGUAGE = 'fr';

function translate(language, key, vars) {
  const dictionary = TRANSLATIONS[language] || TRANSLATIONS[DEFAULT_LANGUAGE];
  let text = dictionary[key];
  if (text === undefined) {
    text = TRANSLATIONS[DEFAULT_LANGUAGE][key];
  }
  if (text === undefined) {
    return key;
  }
  if (vars) {
    for (const [name, value] of Object.entries(vars)) {
      text = text.split(`{${name}}`).join(String(value));
    }
  }
  return text;
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { TRANSLATIONS, DEFAULT_LANGUAGE, translate };
}
