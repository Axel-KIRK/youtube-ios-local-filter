# Développer l'app iOS

## Ce qui est implémenté

`LocalFilterCore` est un package Swift sans dépendance téléchargée. Il utilise CryptoKit, CommonCrypto et zlib fournis par les plateformes Apple. Il porte le traitement du prototype :

- Parsing Protobuf borné, conservation des octets inconnus et retrait des champs 7/45/68 dans un PlayerResponse reconnu.
- Réponses API `/player` et `/get_watch`.
- Réécriture incrémentale UMP, enveloppes Onesie 0 et 25, HMAC vérifié, AES-CTR, gzip borné, IV frais et nouveau HMAC.
- Transmission des médias à l'identique, retour à l'original sur format inconnu, troncature, absence de clé ou échec d'authentification.
- Cache de clés hotconfig en mémoire, lié au client, expiration et limite de 32 entrées.
- Frontière d'intégration HTTP avec contrôle exact des hôtes et chemins.

Le code de `ResponseProcessor` **n'ouvre aucune connexion**. Un futur transport devra lui fournir les réponses déjà déchiffrées par le MITM, appliquer les changements d'en-têtes nécessaires, retirer `x-youtube-hot-hash-data` lorsque `needsFreshConfiguration` le demande, et gérer les annulations et la contre-pression. Il ne faut jamais convertir une sortie vide intermédiaire du flux en fin de réponse HTTP.

Chaque flux et son cache doivent être utilisés sur un même exécuteur série. Les diagnostics sont limités à 64 événements non consommés par réponse ; le consommateur les récupère avec `drainEvents()`. Les clés ne sont pas écrites sur disque. Les limites de mémoire du futur processus réseau restent à mesurer sur appareil.

## Tests Swift

Sur un Mac équipé de Xcode complet et Swift 6 (XCTest n'est pas présent dans toutes les installations des seuls Command Line Tools) :

```sh
swift test
```

Avec les seuls Command Line Tools, le moteur peut aussi être compilé et son diagnostic synthétique exécuté sans XCTest :

```sh
swift run local-filter-check
```

Les fixtures `Tests/LocalFilterCoreTests/Fixtures/onesie.json` sont générées par le moteur Python à partir de données fictives. Elles permettent de vérifier le portage sur les deux enveloppes, avec et sans gzip, sans publier de trafic utilisateur. Leur clé `00 01 … 1f` est une constante de test publique. Pour les régénérer dans l'environnement du prototype :

```sh
.venv-https/bin/python scripts/generate-fixtures.py
```

## Projet iOS

Le code SwiftUI est dans `ios/App`. Il propose un parcours d'installation lisible et une vérification locale du moteur. Il affiche explicitement un filtre inactif : **ni proxy local, ni extension VPN, ni autorité de certification ne sont encore connectés dans cette version**. Aucun profil n'est installé et aucune confiance n'est modifiée.

Avec Xcode complet et XcodeGen installés :

```sh
xcodegen generate --spec ios/project.yml
open ios/LocalFilter.xcodeproj
```

Pour compiler sans signature dans le simulateur :

```sh
xcodebuild -project ios/LocalFilter.xcodeproj -scheme LocalFilter \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

La CI exécute les tests Swift, compile cette app pour le simulateur, puis vérifie séparément les tests Python et la régénération des fixtures. Le [premier passage complet](https://github.com/Axel-KIRK/youtube-ios-local-filter/actions/runs/39141149318), sur le commit `798ebfc945ee75a517296383c78b4cc31a8093da`, a réussi : **16 tests Swift, 48 tests Python, fixtures régénérées à l'identique, compilation simulateur réussie**. Le résultat durable est dans [native-validation.json](../evidence/native-validation.json).

Une compilation simulateur ne prouve pas un fonctionnement réseau sur iPhone. L'installation sur appareil et TestFlight nécessitent la signature et les capacités du compte Apple du projet ; aucun compte ni profil n'est embarqué.

## Prochain jalon

Implémenter et mesurer le proxy HTTPS local maintenu en fonctionnement lorsque YouTube est ouverte, y raccorder le moteur et créer une autorité privée propre à l'installation. Reproduire ensuite le démarrage sans pub **Mac déconnecté**, puis simplifier le guide d'installation. Les conditions de distribution sont distinguées des possibilités techniques dans [l'architecture](IOS-ARCHITECTURE.md).
