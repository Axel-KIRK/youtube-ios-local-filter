# Essais YouTube iOS du 18 octobre 2026

## Résultat à conserver

La méthode qui a donné un résultat positif est **le retrait des instructions publicitaires dans les réponses de démarrage du lecteur**, avant leur livraison à l'application YouTube. Le blocage des octets vidéo publicitaires, même avec le bon identifiant, faisait attendre le lecteur et a été désactivé.

Le résultat a été obtenu dans l'app officielle sur **iPhone SE de 3e génération (iPhone14,6), iOS 18.6.1, build 22G90**. La version exacte de YouTube n'a pas été consignée. La connexion utilisait un proxy Wi-Fi sur Mac et une autorité de certification locale installée puis explicitement approuvée sur le téléphone. Aucun remplacement de YouTube ni jailbreak n'a été utilisé.

Entre **15:07:35 et 15:13:24 UTC** (17:07:35–17:13:24 à Paris), les journaux contiennent **43 réponses modifiées, 41 identifiants distincts, 93 occurrences de `playerAds` et 42 de `adSlots` retirées**. L'utilisateur a confirmé que les changements de vidéo étaient manuels et qu'aucune pub n'était apparue pendant cette séquence. Une capture d'accessibilité a confirmé la vidéo principale à 40 secondes sur 4 min 19. Les captures suivantes montraient une progression, sans toutes contenir le contrôle temporel.

Les 41 identifiants incluent les contenus traités par le réseau : ce n'est pas la preuve que 41 vidéos ont été regardées intégralement. Les compteurs de champs ne sont pas des compteurs de publicités évitées. Le blocage historique de trois familles de domaines était encore actif : la contribution du retrait des instructions n'a pas été isolée par un essai A/B contrôlé, même si le blocage de domaines seul avait déjà échoué.

Après cette séquence, l'utilisateur a dit « mais du coup c'est bloqué sur les pub ». Cette phrase pouvait désigner un lecteur figé ou le périmètre du filtrage. L'inspection qui a suivi montrait une vidéo principale et des téléchargements réussis ; la demande de clarification n'a pas reçu de réponse avant la demande de documentation. **Ce dernier signalement reste non résolu.** Le projet ne doit pas être présenté comme fiable sur tous les démarrages.

## Environnement et réglages finaux

| Élément | Valeur ou rôle |
| --- | --- |
| Application testée | YouTube officielle, iOS ; pas Safari |
| Proxy d'entrée | Python, TCP 8877 sur l'adresse Wi-Fi du Mac, clients explicitement autorisés |
| Relais HTTPS | mitmproxy 12.2.3, Python 3.13.15, `127.0.0.1:8880` |
| Tableau de bord | Python, `http://127.0.0.1:8878` |
| Python du proxy et tableau | 3.14.7 pendant la session ; bibliothèque standard |
| Diagnostic USB | pymobiledevice3 11.35.0, environnement Python séparé |
| `mode.txt` | `block` : trois familles de domaines publicitaires historiques |
| `inspection/https-mode.txt` | `observe-media` : API ciblées et `googlevideo.com` déchiffrés localement |
| `inspection/ad-program-mode.txt` | `remove` : retrait de programmation activé |
| `inspection/video-filter.json` | `enabled: false` ; ancien choix automatique/45 s sans effet sur les médias |
| USB et mode développeur | Utilisés pour observer l'écran ; pas nécessaires au fonctionnement du proxy |

Les modes HTTPS et de retrait sont indépendants : le nom `observe-media` n'implique pas que tout est transmis sans modification lorsque `ad-program-mode` vaut `remove`.

## Chronologie des essais

Toutes les heures ci-dessous sont en **UTC, le 18 octobre 2026**. Ajouter deux heures pour l'heure de Paris ce jour-là.

| Heure | Essai et constat | Conclusion |
| --- | --- | --- |
| Vers 12:24 | Proxy testé depuis le Mac : page locale OK, CONNECT YouTube OK avec TLS vérifié, domaine publicitaire refusé, destination privée refusée. | Transport et contrôles d'accès validés côté Mac seulement. |
| 12:26:30 puis 12:27 | L'iPhone confirme `http://poc.test`. Trafic YouTube/API/googlevideo observé. | Le trafic du téléphone passe par le proxy dans cet essai. |
| Première baseline | Deux pubs sur la première vidéo, plusieurs vidéos sans pub, puis deux autres pubs. Nombre exact de lectures non relevé. | La diffusion est intermittente ; une vidéo sans pub ne démontre rien seule. |
| 12:31:43 | Activation du blocage de `doubleclick.net`, `googleadservices.com`, `googlesyndication.com` et leurs sous-domaines. Fermeture des tunnels antérieurs. | La liste de domaines est effectivement appliquée. |
| 12:34:52 | Une pub visible malgré 20 connexions publicitaires refusées et 39 tunnels autorisés dans la phase. L'utilisateur signale ensuite « 3/3 », après le retour à observation. | Échec du blocage de domaines seul ; impossible d'attribuer les trois pubs à une seule phase. |
| 12:39:23–12:40:01 | Pub 1/2 en pause ; blocage réactivé ; pub 2/2 continue. 11 refus et 7 tunnels autorisés, dont 3 googlevideo. | Deuxième échec ; un préchargement antérieur reste possible. |
| Jusqu'à 13:21 | Tableau de bord, bouton Clear, puis cases « Pub ? » par ligne. Ajout des IP, octets, durées et événements de fermeture par tunnel. | Outils de corrélation, pas classification automatique des pubs. |
| Vers 13:31–13:45 | Inspection native, après activation consentie du mode développeur et accès USB. Observation des séries de pubs et de la transition vers la vidéo. | L'écran peut être observé ; l'app ne fournit pas de DOM Web exploitable ici. |
| Vers 13:50 | Lecture de projets publics de blocage/réécriture. Aucun script externe installé sur l'iPhone ni worker tiers utilisé. | Piste : agir sur la réponse du lecteur plutôt que sur le nom du serveur média. |
| 14:03 | Préparation HTTPS ciblée et certificat local. Premier lancement YouTube en erreur, avertissement TLS également dans Safari. | Le certificat installé n'avait pas encore la confiance totale. |
| 14:12:57 | Après activation réelle de la confiance : API HTTP 200, `/videoplayback` UMP lisible et lecture possible. | Pas de preuve d'un blocage par certificate pinning dans ce cas ; le premier problème était la confiance iOS. |
| 14:19–14:22 | Extraction du `videoId` dans les en-têtes UMP ; rapprochement avec titre et écran. À 14:21:12, le média principal se télécharge alors que la pub 2/2 a encore 13 s ; la vidéo commence vers 14:21:26. | Téléchargé ne signifie pas affiché ; taille, ordre et simultanéité ne suffisent pas. |
| 14:34:44 | Filtre média par identifiant fixe activé. Une cible incorrecte est ensuite corrigée. | Les autres contenus peuvent être retenus, mais le lecteur reste sur la pub bloquée. |
| Vers 14:40 | Quatre identifiants de créatives trouvés structurellement sous `PlayerResponse.ad_slots`. | Distinction entre contenu principal et créatives prévues possible, sans classifier le CDN. |
| 14:43:51 | Correction d'un bug de streaming : renvoyer `[]`, et non un fragment `b''` intermédiaire, quand aucun octet ne doit partir. | Évite une fin HTTP/1 chunked prématurée. La vidéo principale repart, sans prouver qu'une pub prévue a été sautée. |
| 14:51–14:54 | Sélection automatique de la vidéo depuis la navigation Onesie ; fenêtre de 45 s. Cible correcte détectée à 14:53:03 ; écran à 14:53:13 bloqué sur pub 1/2 à moins d'une seconde. | Détection automatique validée, stratégie de blocage média toujours inadéquate. |
| Vers 14:59 | Désactivation du filtre média ; préparation du retrait des instructions. | Ne plus empêcher les médias de circuler. |
| Vers 15:05 | Première tentative de retrait : enveloppe réelle non reconnue, transmission intacte, pub visible. | Le type Onesie 25 n'utilise pas le même emplacement IV/HMAC que le type 0. |
| 15:07:09 | Première réponse préchargée correctement décodée et réécrite. | Correctif de l'enveloppe type 25 opérationnel sur le trafic réel. |
| 15:07:35 | Nouvelle sélection ; retrait de trois `playerAds` ; vidéo principale observée à 40 s à 15:08:16. | Premier démarrage positif documenté. Trois champs ne signifient pas trois pubs évitées. |
| Jusqu'à 15:13:24 | 43 réponses modifiées, 41 identifiants ; utilisateur : nombreux changements manuels, zéro pub. Aucun nouveau `/next` marqué `isAdPlayback` dans la fenêtre contrôlée. | Succès expérimental de session, à reproduire sur d'autres conditions. |
| Ensuite | Dernier signalement ambigu de blocage ; contrôle montrant un média principal en cours. | Clarification et répétition nécessaires avant de conclure à une régression ou à une stabilité générale. |

### Ce que les premiers compteurs mesuraient

À 12:32:24, 8 tunnels vers les familles publicitaires avaient été vus depuis l'iPhone, tous dans la phase d'observation : 3 `ad.doubleclick.net`, puis un pour chacun de `googleads.g.doubleclick.net`, `tpc.googlesyndication.com`, `ade.googlesyndication.com`, `pagead2.googlesyndication.com`, `www.googleadservices.com`. Il y avait aussi 107 tunnels googlevideo. Ce relevé compte des connexions TLS, pas des publicités ni toutes les requêtes HTTP qu'elles contiennent.

Les 20 refus du premier échec se répartissaient en 3 `ad.doubleclick.net`, 6 `googleads.g.doubleclick.net`, 3 `tpc.googlesyndication.com`, 3 `pagead2.googlesyndication.com` et 5 `ade.googlesyndication.com`. Les reprises et nouvelles tentatives peuvent multiplier ces nombres sans nouvelle publicité.

Les hôtes suspectés `rr5---sn-u125g5-5w.googlevideo.com` et `rr1---sn-2o25g5-52.googlevideo.com` n'ont pas constitué des règles fiables : ces serveurs peuvent transporter des contenus différents. Les octets déjà en cache ne sont pas retirés par un blocage ultérieur.

### Cases manuelles et captures

La première case globale « Une pub est à l'écran » était restée cochée environ neuf minutes : elle ne permettait pas une attribution fiable. Les cases par connexion ont ensuite servi à conserver les hypothèses de l'utilisateur. Elles ne bloquent pas la ligne cochée. Clear masque l'historique dans l'interface ; il ne détruit ni les journaux ni les annotations.

L'accès natif a permis des captures d'écran, l'énumération de l'accessibilité et la relance de YouTube. Les commandes d'appui d'accessibilité envoyées n'ont pas déclenché Lire. L'essai de contrôle tactile HID a renvoyé l'erreur 9021 et une exigence de version iOS dans ce service. Ce constat ne signifie pas que toute automatisation iOS exige cette version. Garder l'écran éveillé ne rend pas ces clics possibles. L'utilisateur a donc continué de choisir les vidéos.

## Pourquoi le blocage média faisait attendre

La stratégie abandonnée associait chaque bloc UMP à un en-tête `MEDIA_HEADER`, puis autorisait seulement l'identifiant choisi. Elle pouvait effectivement retenir une créative publicitaire. Mais elle laissait intactes les instructions demandant au lecteur de jouer cette créative. L'écran restait alors dans son état publicitaire.

La fenêtre automatique de 45 s corrigeait le choix manuel de la cible, pas cette attente. Elle était évaluée au début d'une réponse : son expiration autorisait les nouvelles réponses, sans garantir le déblocage immédiat d'une réponse déjà filtrée ni de l'état du lecteur.

L'idée d'un événement de fin de pub ou d'un clic Ignorer a conduit à chercher la commande de lecture. La solution effectivement utilisée **ne fabrique ni fin de pub, ni clic, ni événement de vue** : elle retire la programmation avant qu'elle soit interprétée.

## Mécanisme final

```text
YouTube officielle sur iPhone
    → proxy Wi-Fi autorisé sur Mac (8877)
    → MITM HTTPS local (8880, seulement API YouTube + googlevideo)
    → réponse du serveur
    → décodage de la programmation du lecteur
    → retrait ciblé des champs publicitaires
    → réponse réauthentifiée et rechiffrée vers l'iPhone
    → médias transmis en streaming
```

`inspection/ad_program.py` reconnaît un `PlayerResponse` par `videoDetails` (champ 11, ID dans le champ 1) et la présence d'un champ de lecture 2 ou 4. Il retire uniquement les occurrences de type Protobuf « length-delimited » des champs suivants :

| Champ | Nom | Action |
| --- | --- | --- |
| 7 | `playerAds` | Retirer les instructions associées |
| 45 | `adPlacements` | Même traitement ; supporté, pas compté dans la séquence positive |
| 68 | `adSlots` | Retirer les emplacements publicitaires |

Les champs inconnus restent sérialisés à l'identique. L'API `/player` peut contenir directement la réponse ; `/get_watch` utilise un champ répété 1 contenant un `GetWatchResponse`, puis son champ 2. Le réécrivain final traite le Protobuf, pas les variantes JSON.

### UMP et Onesie

Le flux UMP découpe données de contrôle et médias. Son encodage d'entiers n'est pas le varint Protobuf : confondre les deux donne un décodage erroné. Les parties de contrôle 10 et 11 sont associées ; les autres parties, dont les médias, traversent le filtre sans modification.

- **Type Onesie 0** : les paramètres cryptographiques sont dans le champ 4 du header. HMAC au champ 4, IV au 5, compression au 6 de ces paramètres. Le corps décodé est une enveloppe de succès (`1 = 1`, `2 = 200`) dont le champ 4 contient le PlayerResponse.
- **Type Onesie 25, confirmé en production pendant cet essai** : la partie UMP 11 contient `EncryptedInnertubeResponsePart`. Ses champs 1, 2, 3, 4 portent respectivement texte chiffré, HMAC, IV, compression. Après déchiffrement, les champs 4 répétés contiennent les GetWatchResponse ; le PlayerResponse est leur champ 2. Chercher ces paramètres seulement dans le header était le défaut de la première tentative.

Le code vérifie HMAC-SHA256 sur `ciphertext || IV`, déchiffre en AES-128-CTR avec les 16 premiers octets de la clé de 32 octets, et utilise les 16 derniers pour le HMAC. Il décompresse gzip si demandé, réécrit, recompresse, génère un nouvel IV de 16 octets puis recalcule le HMAC. Il ne déchiffre pas un DRM vidéo.

Les clés Onesie viennent de la configuration « hotconfig » retournée par l'API : chemin `1 → 16 → 7` (ou champ 3 encodé en base64), puis `138536474 → 146311580`. La clé est au champ 1, la clé enveloppée au 2, le TTL au 3. Le rapprochement utilise l'empreinte SHA-256 de la clé enveloppée et le client. Le cache reste en mémoire, limité à 32 entrées et au plus une heure. Sans clé disponible, l'en-tête de cache `x-youtube-hot-hash-data` de `/log_event` est retiré pour permettre de récupérer une configuration fraîche.

Une réponse inconnue, trop grande, tronquée, non authentifiée ou sans clé est retransmise intacte. La limite des blocs de contrôle est 4 Mio, y compris la décompression. **Ce repli privilégie la lecture et peut laisser passer une publicité.** La mémoire et le streaming doivent être réévalués lors du portage iOS.

### Identifiants publicitaires

Quatre créatives ont été identifiées sous `PlayerResponse.ad_slots`, avec des durées de **6, 15, 144 et 344 secondes**. Leur présence dans cette structure prouve qu'elles font partie de la programmation publicitaire reçue, pas qu'elles ont toutes été téléchargées ou affichées. Une pub de 344 s réfute aussi l'idée qu'une pub est toujours plus courte que la vidéo principale.

Le chemin observé vers leurs VideoDetails était : `68 → 424701016 → 2 → 1 → 500272857 → 2 → 500604390 → 1[index 0 ou 1] → 500272857 → 2 → 61554017 → 1 → 11`. Dans VideoDetails, les champs 1, 15, 16 et 33 donnaient ID, titre, durée et auteur. Ce chemin est une observation d'un schéma privé susceptible de changer, pas une API contractuelle.

## Vérifications et performances

**48 tests automatisés ont passé** sur le prototype final. Ils couvrent le format UMP fragmenté, les limites de mémoire, l'association des identifiants, la fenêtre automatique, l'authentification Onesie, les deux enveloppes, la conservation des médias et champs inconnus, les données tronquées et les contrôles du tableau de bord. Après ajout des mesures temporelles, les 14 tests de retrait et d'intégration HTTP ont été repassés. Le JavaScript du tableau a aussi passé `node --check`.

Le correctif de fragment vide est essentiel : avec mitmproxy, un callback de streaming qui n'a encore rien à envoyer renvoie `[]`. Renvoyer `b''` au milieu d'une réponse HTTP/1 chunked pouvait être interprété comme la fin de la réponse.

Dans les dix mesures finales conservées, le traitement de la réécriture prend environ **1,8–2,3 ms**, l'attente du bloc de contrôle **4–50 ms**, et le temps depuis la demande jusqu'à la réponse utile **0,42–1,31 s**. Ce dernier temps comprend le réseau et le serveur ; il n'est pas le coût du filtre. Le petit délai initial ressenti par l'utilisateur n'a pas été attribué avec certitude. Des annulations et quelques erreurs API sont apparues pendant les changements rapides de vidéo, sans mesure de causalité.

## Ce qui reste à vérifier

- Clarifier et reproduire le dernier signalement de blocage, avec heure, capture et réponse correspondante.
- Refaire une comparaison observation/retrait/observation sur les mêmes conditions ; désactiver séparément le blocage de domaines pour isoler les effets.
- Tester démarrage à froid, renouvellement de clés, arrêt/redémarrage du relais, vidéos longues et pubs intermédiaires.
- Tester Shorts, direct, changement de compte, version YouTube différente et deuxième iPhone ; rien de cela n'est acquis.
- Mesurer batterie, mémoire, latence et stabilité d'une app autonome.
- Valider un chemin réseau iOS déployable sur téléphone personnel, puis une installation TestFlight/App Store accessible au grand public.

## Conservation des preuves

[session-summary.json](../evidence/session-summary.json) contient les nombres, horaires, configuration et échantillons de durée publiables. [source-manifest.json](../evidence/source-manifest.json) relie les fichiers source originaux à leur copie publique par SHA-256. Les adresses de test ont été remplacées et l'adresse du téléphone du tableau rendue configurable.

Les preuves brutes restent dans le dossier local du prototype : `events.jsonl`, `inspection/https-events.jsonl`, `ad-identification-proof.json`, `ump-prefetch-proof.json`, `video-filter-verification.json`, `ad-program-verification.json`, captures natives et `latest-tests.txt`. Elles ne sont pas incluses dans GitHub : les réponses API peuvent contenir des URL signées ou des informations de compte. Les clés de l'autorité TLS restent également privées. Les anciens fichiers `LISEZMOI.txt` et `VERIFICATION.txt` sont des archives chronologiques ; leurs premières consignes ne décrivent plus l'état final.

## Références techniques

- [YouTube-X, hooks du lecteur](https://github.com/PoomSmart/YouTube-X/blob/main/Tweak.x) : piste du retrait des champs publicitaires ; aucune injection de ce tweak dans notre app.
- [Maasea, réécriture de réponse](https://github.com/Maasea/sgmodule/blob/master/Script/Youtube/youtube.response.js) et [requête](https://github.com/Maasea/sgmodule/blob/master/Script/Youtube/youtube.request.js) : structures et crypto étudiées ; aucun worker Maasea utilisé.
- [UMP](https://github.com/davidzeng0/innertube/blob/main/googlevideo/ump.md), [initplayback](https://github.com/davidzeng0/innertube/blob/main/googlevideo/initplayback.md), [EncryptedInnertubeResponsePart](https://github.com/davidzeng0/innertube/blob/main/protos/video_streaming/encrypted_innertube_response_part.proto), [PlayerResponse](https://github.com/davidzeng0/innertube/blob/main/protos/youtube/api/innertube/player_response.proto).
- [MediaHeader](https://github.com/LuanRT/googlevideo/blob/main/protos/video_streaming/media_header.proto) et [exemple Onesie](https://github.com/LuanRT/googlevideo/tree/main/examples/onesie-request).
- [Streaming mitmproxy](https://docs.mitmproxy.org/stable/addons/examples/#example-http-stream-modify-py).

