# Reproduire le prototype testé

Cette procédure reproduit le **prototype Mac + iPhone**, pas encore l'objectif d'app autonome. Elle utilise la copie publique des sources ; les environnements, journaux et certificats de la session ne sont pas distribués.

## Préparer le Mac

Utiliser Python 3.13 pour le relais HTTPS. Les dépendances exactes observées sur macOS arm64 sont dans `reference/requirements-https.lock.txt`. Le proxy et le tableau de bord utilisent la bibliothèque standard. Depuis la racine du dépôt :

```sh
python3.13 -m venv .venv-https
.venv-https/bin/python -m pip install -r reference/requirements-https.lock.txt
cd reference/proxy
```

Ce verrouillage capture l'environnement de la session. Son installation et les 48 tests ont aussi réussi dans un environnement GitHub Actions macOS 15 neuf ; la configuration complète d'un deuxième couple Mac/iPhone reste à refaire. Ne pas mélanger cet environnement avec pymobiledevice3, dont les dépendances cryptographiques diffèrent. `reference/requirements-inspection.lock.txt` conserve les versions de diagnostic USB, qui ne sont pas nécessaires pour filtrer.

Relever l'adresse Wi-Fi actuelle du Mac et celle de l'iPhone. Les deux doivent communiquer sur le réseau local. Les IP de la session étaient temporaires et ne doivent pas être réutilisées aveuglément. Sur le Mac, `lsof -nP -iTCP:8877 -iTCP:8878 -iTCP:8880 -sTCP:LISTEN` permet de repérer des services déjà démarrés ; ne pas lancer une seconde instance sur les mêmes ports.

## Démarrer les trois services

Dans trois terminaux, chacun placé dans `reference/proxy` :

**1. Relais HTTPS** — rester en fonctionnement ; au premier démarrage mitmproxy crée une autorité locale dans le dossier privé indiqué.

```sh
umask 077
mkdir -p inspection/https-ca
../../.venv-https/bin/mitmdump \
  --listen-host 127.0.0.1 --listen-port 8880 \
  --set "confdir=$PWD/inspection/https-ca" \
  --set connection_strategy=lazy --set ssl_insecure=false \
  --set onboarding=false --set flow_detail=0 \
  --set termlog_verbosity=error --set stream_large_bodies=4m \
  -s inspection/https_addon.py
```

**2. Proxy d'entrée** — remplacer les deux valeurs d'exemple par les IP réelles :

```sh
POC_MAC_IP='192.0.2.10'
POC_PHONE_IP='192.0.2.20'
python3 -u proxy.py --listen "$POC_MAC_IP" \
  --allow-client "$POC_PHONE_IP" --allow-client "$POC_MAC_IP"
```

Ces adresses `192.0.2.*` sont des exemples de documentation. Le proxy n'accepte que les clients autorisés et localhost. Il refuse les destinations privées et les ports autres que 443. Le relais HTTPS reste sur localhost.

**3. Tableau de bord** — remplacer à nouveau l'IP d'exemple :

```sh
POC_PHONE_IP='192.0.2.20' python3 -u dashboard/server.py
```

Ouvrir `http://127.0.0.1:8878` sur le Mac. Le réglage `POC_PHONE_IP` sert à l'affichage de l'état automatique historique ; le contrôle d'accès réseau dépend bien des arguments du proxy.

## Installer le certificat et configurer l'iPhone

Les fichiers distribués démarrent en observation, sans déchiffrement. Sur l'iPhone, noter le réglage de proxy Wi-Fi précédent, puis choisir Réglages → Wi-Fi → ⓘ → Configurer le proxy → Manuel. Renseigner IP du Mac, port **8877**, authentification désactivée.

1. Ouvrir `http://poc.test` dans Safari ; vérifier « Connexion au proxy : OK ».
2. Ouvrir `http://poc.test/youtube-poc.cer`, autoriser le téléchargement, puis installer le profil dans Réglages → Général → VPN et gestion de l'appareil, ou « Profil téléchargé ».
3. Dans Réglages → Général → Informations → Réglages des certificats, activer la **confiance totale** pour cette autorité uniquement. Installer le profil sans cette étape a causé l'échec TLS initial de notre essai.

Le nom de l'autorité générée par mitmproxy peut différer du nom personnalisé utilisé pendant la session. Vérifier le certificat local avant de lui faire confiance ; sa clé privée ne doit jamais quitter le Mac ou être commise dans Git. Safari sert uniquement à l'installation et au diagnostic ; la lecture testée reste dans YouTube. [Instructions Apple](https://support.apple.com/en-us/102390)

## Retrouver la configuration finale

Après l'installation et la confiance, depuis `reference/proxy` :

```sh
python3 - <<'PY'
import json
from pathlib import Path
Path('mode.txt').write_text('block\n')
Path('inspection/https-mode.txt').write_text('observe-media\n')
Path('inspection/ad-program-mode.txt').write_text('remove\n')
Path('inspection/video-filter.json').write_text(json.dumps({
    'enabled': False, 'videoId': 'demoVideo01',
    'mode': 'auto', 'windowSeconds': 45
}) + '\n')
PY
```

L'ID indiqué est un exemple inactif : **aucune cible n'est nécessaire** au retrait de programmation. Ne pas activer simultanément l'ancien filtre « Vidéo autorisée ». Le tableau empêche cette combinaison lorsqu'on passe par ses boutons.

Un changement du mode HTTPS ou de la configuration du filtre média ferme les tunnels existants. Un changement de programmation agit sur les nouvelles réponses. Fermer complètement YouTube, rouvrir et choisir une vidéo pour éviter de tirer une conclusion d'une ancienne réponse en cache.

Les clés Onesie sont en mémoire seulement. Après redémarrage du relais, elles doivent être récupérées dans une nouvelle réponse de configuration. Un premier chargement sans clé peut être transmis intact et contenir une pub. Le code tente de récupérer une configuration fraîche via `/log_event` ; ce mécanisme ne promet pas que le premier chargement de toute session sera filtré.

## Contrôler le résultat

Dans le panneau « Programmation publicitaire », l'état doit être `remove` et le filtre par identifiant désactivé. Les événements `ad_program` doivent afficher `status: decoded`, `modified: true`, l'ID et les champs retirés. `modified` sur une réponse ne signifie pas que des octets vidéo ont été bloqués.

Pour résumer les derniers événements sans imprimer de corps API :

```sh
python3 - <<'PY'
import json
from pathlib import Path
p = Path('inspection/https-events.jsonl')
rows = [json.loads(line) for line in p.read_text().splitlines() if line]
for e in [r for r in rows if r.get('event') == 'ad_program'][-10:]:
    print(e.get('time'), e.get('status'), e.get('modified'), e.get('players'))
PY
```

Noter, pour chaque sélection, l'heure, le titre localement, une éventuelle pub, un éventuel blocage et le début réel de la vidéo. Alterner au tableau les modes « retirer » et « observer » sur plusieurs lectures. Le changement de mode n'efface pas les caches. Pour isoler le retrait de programmation, refaire aussi l'essai avec `mode.txt` en `observe` ; cela n'a pas été mesuré de façon contrôlée lors de la session initiale.

## Tests du code

Depuis `reference/proxy` :

```sh
PYTHONPATH=dashboard ../../.venv-https/bin/python -m unittest \
  inspection.test_ad_program inspection.test_navigation \
  inspection.test_https_filter inspection.test_ump_filter \
  inspection.test_ump_inspect inspection.test_api_inspect \
  test_flow_metrics dashboard.test_annotations -q
```

Résultat de référence : **48 tests passent**. Ils n'exécutent pas YouTube sur un téléphone et ne remplacent pas le contrôle de lecture.

## Diagnostic rapide

| Symptôme | Contrôle utile |
| --- | --- |
| Tout le réseau du téléphone semble arrêté | Vérifier que le Mac est éveillé et que 8877 écoute ; restaurer le réglage de proxy antérieur si nécessaire. |
| Erreur certificat ou chargement impossible | Vérifier confiance totale et bon certificat, puis que 8880 écoute ; ne pas désactiver la vérification TLS amont. |
| Pub figée | Vérifier d'abord `video-filter.json: enabled=false`. Conserver heure et événement ; ne pas supposer que retenir plus de médias aidera. |
| Pub visible, `key_or_crypto_unavailable` ou `unrecognized_or_unauthenticated` | Le repli transmet l'original. Contrôler nouvelle configuration de clés et format ; ne pas compter cette réponse comme filtrée. |
| Aucun événement lié à la nouvelle vidéo | Contrôler proxy, cache, VPN, réseau cellulaire ou chemin contournant le proxy ; aucune efficacité ne peut être déduite du silence. |
| Vidéo sans pub mais aucun retrait journalisé | Une pub n'était peut-être pas prévue. Ce démarrage ne prouve pas l'efficacité du filtre. |

## Arrêter et conserver

Pour arrêter seulement la réécriture, décocher le panneau de programmation (mode `observe`) en laissant le filtre média désactivé. Pour arrêter le déchiffrement, écrire `off` dans `inspection/https-mode.txt` ; conserver le proxy en marche tant qu'il reste configuré sur l'iPhone.

Pour terminer complètement : **restaurer d'abord le proxy Wi-Fi antérieur sur l'iPhone**, puis arrêter les trois services avec Ctrl-C. Le profil de certificat de ce test peut ensuite être retiré dans VPN et gestion de l'appareil. Ne retirer aucun autre profil. Le mode développeur utilisé pour les captures peut être désactivé séparément ; il ne fait pas partie du parcours nécessaire au filtre.

Le dossier `inspection/https-ca` doit être conservé de façon privée si l'on veut retrouver la même confiance sans réinstaller le certificat. S'il est perdu, générer une nouvelle autorité et refaire l'installation sur le téléphone. Git conserve le code et les mesures publiables, pas cette clé.
