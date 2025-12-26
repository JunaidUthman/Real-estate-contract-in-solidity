# 🏠 Intégration Blockchain — Guide Frontend (Angular)

Ce guide explique comment lancer le **backend blockchain en local** et comment connecter ton application **Angular** au smart contract **RealEstateRental**.

---

## ⚙️ 1. Installation et lancement (à faire en premier)

Pour que l’application fonctionne, tu dois exécuter une **blockchain locale** sur ta machine.
C’est l’équivalent de lancer un serveur API / base de données en local.

### Étape 1 : Démarrer le nœud local

Ouvre un terminal dans le **dossier du projet blockchain** (pas le dossier Angular) et lance :

```bash
npx hardhat node
```

> ⚠️ **IMPORTANT**
> Ne ferme jamais ce terminal !
> Il affiche une liste de **20 comptes de test** avec leurs **clés privées**. Garde-le ouvert.

---

### Étape 2 : Déployer le contrat

Ouvre un **deuxième terminal** (toujours dans le dossier blockchain) et lance :

```bash
npx hardhat run scripts/deploy.js --network localhost
```

Si tout se passe bien, tu verras le message :

> ✅ **Fichiers ABI et adresse envoyés au dossier frontend !**

---

### Étape 3 : Configurer MetaMask (navigateur)

1. Ouvre l’extension **MetaMask**

2. Ajoute un réseau manuellement :

   * **Nom du réseau** : Localhost 8545
   * **URL RPC** : [http://127.0.0.1:8545](http://127.0.0.1:8545)
   * **ID de chaîne** : 31337
   * **Symbole** : ETH

3. Importe un **compte de test** :

   * Copie une **Private Key** affichée dans le *Terminal 1*
   * Importe-la dans MetaMask pour obtenir des **ETH fictifs**

---

## 📂 2. Fichiers de configuration

Le script de déploiement crée automatiquement (ou met à jour) deux fichiers dans ton projet Angular
(généralement dans `src/contracts/`) :

* **`contract-address.json`**
  Contient l’adresse du contrat (ex : `0x5Fb...`).
  C’est l’URL de notre **API blockchain**.

* **`RealEstateRental.json`**
  Contient l’**ABI**.
  C’est la liste des fonctions disponibles.

### Utilisation dans un service Angular

```ts
import { ethers } from 'ethers';
import RentalABI from './contracts/RealEstateRental.json';
import ContractAddress from './contracts/contract-address.json';
```

---

## 🔌 3. Liste des fonctions (endpoints)

> ⚠️ Les montants (prix) doivent être **convertis en Wei**
> (voir la section **Notes utiles** plus bas).

---

## 🅰️ Fonctions pour les propriétaires (Landlords)

### `listProperty`

Crée une nouvelle annonce immobilière.

* `propertyAddress` *(string)* : adresse physique du bien
* `description` *(string)* : description du bien
* `rentBaseAmount` *(BigInt / string)* : loyer (**en Wei**)
* `securityDeposit` *(BigInt / string)* : caution (**en Wei**)
* `unit` *(number)* : fréquence de paiement

  * `0` → Mensuel
  * `1` → Journalier

---

### `updateProperty`

Met à jour une annonce existante.

* `propertyId` *(number)* : ID de la propriété
* `propertyAddress` *(string)* : nouvelle adresse
* `description` *(string)* : nouvelle description
* `rentBaseAmount` *(BigInt)* : nouveau loyer
* `securityDeposit` *(BigInt)* : nouvelle caution
* `isAvailable` *(boolean)* : `true` si disponible, `false` sinon
* `unit` *(number)* : `0` (Mensuel) ou `1` (Journalier)

---

### `delistProperty`

Retire (archive) une propriété.

* `propertyId` *(number)* : ID de la propriété

---

## 🅱️ Fonctions pour les locataires (Tenants)

### `reserveProperty` *(PAYABLE 💰)*

Le locataire réserve le bien.
L’argent est envoyé au **contrat (escrow)**, pas encore au propriétaire.

* `propertyId` *(number)* : ID du bien
* `durationInMonths` *(number)* : nombre de mois (0 si journalier)
* `optionalAdditionalDays` *(number)* : nombre de jours (0 si mensuel)

**Transaction (`value`)** :
Premier loyer + caution

---

### `activateAgreement`

Le locataire confirme qu’il a reçu les clés.
➡️ Déclenche le paiement du **premier loyer** au propriétaire.

* `agreementId` *(number)*

---

### `payRent` *(PAYABLE 💰)*

Paie le loyer suivant.

* `agreementId` *(number)*
* `amountInUnits` *(number)* : toujours `1`

**Transaction (`value`)** :
Montant exact d’un loyer.

> ❌ Cette fonction échoue si le délai (25 jours ou 1 jour) n’est pas écoulé.

---

### `terminateAgreement`

Le locataire quitte le logement **avant la fin** du contrat.

* `agreementId` *(number)*

**Conséquence** :
➡️ Le propriétaire récupère la **caution** (pénalité).

---

### `completeAgreement`

Le locataire quitte le logement **à la fin normale** du contrat.

* `agreementId` *(number)*

**Condition** : la date de fin doit être passée.
**Conséquence** : le locataire récupère sa **caution**.

---

## 🔍 4. Fonctions de lecture (Getters)

Ces fonctions :

* ne consomment **pas de gas**
* ne nécessitent **pas MetaMask**
* utilisent uniquement un **provider de lecture**

### `getAvailableProperties()`

Retourne un tableau d’IDs correspondant aux biens disponibles :

```ts
[1, 2, 5]
```

---

### `getProperty(id)`

Retourne un objet contenant :

* adresse
* description
* prix
* propriétaire
* disponibilité
* etc.

---

### `getRentalAgreement(id)`

Retourne un objet contenant :

* dates de début et de fin
* statut
* total payé
* locataire
* propriétaire

---

## 📝 5. Notes utiles pour Angular

### 💱 Conversion Ether / Wei

La blockchain ne gère pas les virgules.

* **1 ETH = 10¹⁸ Wei**

Afficher un montant :

```ts
ethers.formatEther(amountInWei)
```

Envoyer un montant saisi par l’utilisateur :

```ts
ethers.parseEther("1.5")
```

---

### 📌 Statuts (Enums)

Si tu récupères un `status` depuis le contrat, tu obtiendras un nombre :

* `0` → PENDING_RESERVATION (payé, clés non reçues)
* `1` → ACTIVE (location en cours)
* `2` → COMPLETED (terminé normalement)
* `3` → TERMINATED (rompu avant la fin)
* `4` → DISPUTED (litige)

---

### ❗ Gestion des erreurs

Si une action échoue (ex : payer trop tôt) :

* l’erreur est contenue dans l’objet `error` retourné par **ethers.js**
* cherche le message après **`revert`**
