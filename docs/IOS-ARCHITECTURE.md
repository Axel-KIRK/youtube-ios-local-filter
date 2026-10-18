# Application iOS autonome

## Objectif utilisateur

Installer une app, suivre quelques validations expliquées en français dans Réglages, activer le filtre, puis continuer d'utiliser YouTube officielle. L'utilisateur final ne doit avoir besoin ni d'un Mac, ni d'un terminal, ni du mode développeur, ni d'une application YouTube modifiée. Le périmètre de ce dépôt est **iOS uniquement**.

Ce parcours est un objectif ; le prototype validé dépend encore du Mac. Une distribution TestFlight/App Store est distincte d'une compilation et d'une installation de développement.

## Séparer les fonctions

1. **Moteur de réécriture local** : décoder Protobuf et UMP, authentifier Onesie, retirer les trois champs publicitaires, conserver les médias et restituer l'original sur erreur. Porter ce composant en Swift et le tester indépendamment du réseau.
2. **Transport** : obtenir les réponses HTTPS de YouTube dans un processus iOS qui continue de fonctionner lorsque YouTube est au premier plan. Respecter la validation des certificats amont, les limites mémoire, le flux HTTP et les connexions non ciblées.
3. **Certificat local** : autorité propre à l'installation, clé privée dans le trousseau, export du certificat public seulement, installation et confiance explicites par l'utilisateur.
4. **Interface** : quelques étapes, un état exact (« prêt », « inactif », « erreur »), arrêt accessible, aucun compteur présenté abusivement comme un nombre de pubs évitées.

La suppression par domaine et le filtre média par ID ne doivent pas devenir le mécanisme principal de l'app : ils ont échoué à assurer la lecture sans pub lors du prototype.

## Un proxy autonome existe déjà sur iOS

**Oui, une app peut proposer un proxy HTTPS local sans Mac.** Charles pour iOS et Proxyman pour iOS documentent ce fonctionnement et une distribution App Store. Charles demande l'autorisation d'une configuration VPN, puis l'installation et la confiance de son certificat. Proxyman explique que son VPN dirige le trafic vers un serveur MITM local au téléphone. Ces exemples établissent la faisabilité d'un proxy autonome ; ils ne valident pas encore notre réécriture YouTube dans ce contexte. [Charles, installation](https://www.charlesproxy.com/documentation/ios/getting-started-1/), [Proxyman, architecture et certificat](https://github.com/ProxymanApp/docs/blob/main/proxyman-ios/vpn-and-proxyman-certificate.md)

Le parcours visé est donc : installer notre app, autoriser sa configuration VPN, installer et approuver son certificat une fois, puis activer le filtre. YouTube n'est pas réinstallée. Une version distribuée normalement ne demande pas le mode développeur ; ce mode concerne les essais de développement et de diagnostic.

## Contrainte réseau à résoudre dans notre code

Une app ordinaire ne reçoit pas automatiquement les réponses HTTPS des autres apps. Un bloqueur Safari ne traite pas le trafic de YouTube officielle. Un filtre d'URL ou de domaine seul ne donne pas la réécriture du corps Protobuf nécessaire ici.

`NEPacketTunnelProvider` est une piste d'expérimentation technique. Apple indique néanmoins que l'utiliser comme filtre de contenu ou hôte d'un proxy local ne correspond pas à ses usages pris en charge. Cette réserve documentaire **ne prouve pas l'impossibilité technique ou une interdiction de tout proxy iOS**, comme le montrent les applications existantes. Elle oblige à distinguer fonctionnement pratique, architecture officiellement prise en charge et acceptation de notre propre produit. Les contraintes des autres fournisseurs Network Extension doivent aussi être vérifiées. [TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers), [TN3134](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment)

Un vrai VPN vers un serveur distant serait une autre architecture, avec serveur, coûts et trafic tiers ; ce n'est pas le fonctionnement local visé et il n'est pas déployé dans ce projet. Un proxy dans l'app principale qui disparaît dès qu'iOS la suspend ne satisfait pas non plus le besoin.

La confiance d'un certificat installé manuellement demande une action dans Réglages. Cette étape peut être guidée, pas cachée ou activée silencieusement par l'app. [Apple, confiance des certificats](https://support.apple.com/en-us/102390)

## Critères avant une première version utilisable

- Le moteur Swift passe les mêmes fixtures synthétiques que le moteur Python, y compris les réponses chiffrées et fragmentées.
- Le transport reste opérationnel lorsque YouTube est au premier plan et après verrouillage/reprise.
- La clé de certificat ne sort pas de l'appareil ; aucune autorité partagée entre installations ; aucune collecte de requêtes personnelles.
- Le premier démarrage sans clé, leur renouvellement et un schéma inconnu laissent une lecture possible ; l'interface rend visible l'absence de filtrage.
- Un deuxième iPhone personnel peut être configuré par quelqu'un qui n'a pas participé au développement, sans Mac ni mode développeur.
- Des pubs initiales et intermédiaires, plusieurs sessions et plusieurs versions de YouTube sont testées. Une erreur ou une pub encore visible est consignée avec le bon contexte.
- La signature, les capacités Apple et le canal de distribution sont validés avant de proposer un lien d'installation. [Règles de distribution VPN](https://developer.apple.com/app-store/review/guidelines/#vpn-apps)

## Ordre d'implémentation

Le premier incrément porte le moteur réel en Swift et crée une app de vérification locale. Il ne doit pas afficher « protection activée » sans connexion réelle au trafic de YouTube. L'intégration réseau et la distribution constituent le jalon suivant ; une coquille VPN qui accepte la connexion puis ne transmet aucun paquet serait un défaut, pas un progrès.
