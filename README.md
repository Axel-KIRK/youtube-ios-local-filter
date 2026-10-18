# YouTube iOS Local Filter

Recherche et développement d'un filtre pour **l'application YouTube officielle sur iPhone**. Le principe consiste à retirer les instructions publicitaires envoyées au lecteur, tout en laissant passer les médias.

**État du projet : un prototype avec proxy sur Mac a fonctionné pendant une session réelle. L'app iOS autonome n'est pas encore un bloqueur utilisable.** L'objectif produit est une installation simple, quelques validations dans Réglages, puis un interrupteur — sans ordinateur ni mode développeur pour l'utilisateur final.

## Résultat du 18 octobre 2026

Sur un **iPhone SE de 3e génération, iOS 18.6.1 (22G90)**, le proxy a retiré les champs publicitaires de 43 réponses concernant 41 identifiants vidéo distincts. L'utilisateur a changé manuellement de nombreuses vidéos et n'a observé aucune publicité pendant cette séquence. La progression de la vidéo principale a également été contrôlée.

Ce résultat porte sur une session, avec un certificat local approuvé sur l'iPhone. Il ne mesure pas le nombre de publicités évitées. Un dernier signalement ambigu de blocage reste à clarifier ; il est conservé dans le compte rendu.

## Documentation

- [Compte rendu précis des essais et résultat final](docs/EXPERIMENTS-2026-10-18.md)
- [Reproduire le prototype et revenir en arrière](docs/REPRODUCE.md)
- [Architecture iOS, parcours utilisateur et travail restant](docs/IOS-ARCHITECTURE.md)
- [Moteur Swift, app de vérification et compilation](docs/DEVELOPMENT.md)
- [Mesures publiables de la session](evidence/session-summary.json)
- [Code Python du prototype testé](reference/proxy/)

Le dépôt ne contient ni certificat privé, ni cookies, ni requêtes authentifiées, ni vidéos, ni captures d'écran personnelles. Les fixtures de tests sont synthétiques. La publication du code ne constitue pas une application signée ou une disponibilité sur l'App Store.

## Première implémentation iOS

Le moteur est porté dans `Sources/LocalFilterCore` : Protobuf, flux UMP, enveloppes Onesie 0/25, authentification, réécriture et conservation des médias. `ios/App` contient une première interface SwiftUI qui vérifie ce traitement avec des données fictives. Le raccordement au trafic réel de YouTube et le parcours d'installation du certificat restent à implémenter. L'interface indique donc **filtre inactif**.

```sh
swift test
```
