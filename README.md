# grav-docs

Image Docker pour [Grav CMS](https://getgrav.org/) (Core + Admin), avec
Nginx et PHP-FPM dans un même conteneur, utilisée comme documentation
interne.

Ce dépôt ne contient aucune logique de déploiement : il fournit uniquement
le code nécessaire pour construire et lancer l'image localement.

## Contenu

```
grav-docs/
├── docker/
│   ├── entrypoint.sh         # Initialise le volume utilisateur, lance le bootstrap admin, démarre les services
│   ├── bootstrap-admin.sh    # Création optionnelle d'un compte admin (voir ci-dessous)
│   ├── nginx.conf
│   └── php-fpm.conf
├── grav/
│   └── user/                 # Squelette vide (placeholders), copié dans le volume au premier démarrage
├── Dockerfile
└── docker-compose.yml        # Lancement local uniquement
```

## Volume persistant

Le contenu utilisateur Grav (pages, thèmes, plugins, configuration) est
stocké dans `/var/www/html/user`, qui doit être monté comme volume
persistant.

Au premier démarrage (volume vide), le conteneur copie un squelette minimal
dans ce répertoire et marque l'initialisation comme terminée
(`.initialized`). Les démarrages suivants ne touchent plus à ce contenu.

## Lancer en local

```bash
docker compose build
docker compose up -d
```

Accès :
- Site : [http://localhost:8080](http://localhost:8080)
- Admin : [http://localhost:8080/admin](http://localhost:8080/admin)

```bash
docker compose logs -f      # Voir les logs
docker compose down         # Arrêter
docker compose down -v      # Arrêter et supprimer le volume (perte du contenu)
```

## Bootstrap optionnel d'un compte administrateur

Au démarrage, le conteneur peut créer automatiquement un compte
administrateur Grav, via la CLI officielle du plugin `login`
(`bin/plugin login new-user`).

### Variables d'environnement

| Variable | Description |
|---|---|
| `GRAV_ADMIN_USER` | Nom d'utilisateur du compte à créer |
| `GRAV_ADMIN_PASSWORD` | Mot de passe du compte à créer |
| `GRAV_ADMIN_EMAIL` | Adresse email du compte à créer |

### Comportement

- Si l'une des trois variables est absente, **aucun compte n'est créé** et
  le conteneur démarre normalement.
- Si un compte portant le nom `GRAV_ADMIN_USER` existe déjà dans
  `user/accounts/`, **il n'est jamais écrasé** — le bootstrap est ignoré.
- Le compte est créé avec les permissions Admin + Site (`-P b`).
- Le mot de passe n'est jamais passé en argument de ligne de commande (donc
  jamais visible dans la liste des processus) : il est fourni à la CLI via
  son entrée standard, en mode interactif piloté.
- Si le plugin `login` n'est pas présent dans l'image, le bootstrap échoue
  proprement avec un message explicite dans les logs — aucun mot de passe
  n'est haché manuellement en remplacement.
- Un échec du bootstrap (plugin absent, erreur de validation du mot de
  passe par Grav, etc.) n'empêche jamais le démarrage du conteneur.
- Aucun secret n'apparaît dans les logs du conteneur.

### Exemple local

```bash
GRAV_ADMIN_USER=admin \
GRAV_ADMIN_PASSWORD=ChangeMe123 \
GRAV_ADMIN_EMAIL=admin@example.com \
docker compose up -d
```

Ou en décommentant les lignes correspondantes dans `docker-compose.yml`.

## Publication de l'image

L'image est publiée automatiquement sur GHCR à chaque push sur `main`, via
`.github/workflows/publish-ghcr.yml`.

**Image publiée :** `ghcr.io/sepp67/grav-docs:latest`

## Déploiement

Le déploiement en staging et production est géré exclusivement par le dépôt
[devops_staging_prod_infra](https://github.com/sepp67/devops_staging_prod_infra).

Domaines :
- Staging : `docs.lavallee.local`
- Production : `docs.lavallee.tech`

Les secrets `GRAV_ADMIN_USER`, `GRAV_ADMIN_PASSWORD` et `GRAV_ADMIN_EMAIL`
en staging/production sont injectés par Ansible Vault depuis
`devops_staging_prod_infra` — ce dépôt ne contient et ne génère aucun
secret.

Ce dépôt ne contient pas de logique de déploiement, de rôle Ansible, ni de
variables d'environnement spécifiques à un environnement.
