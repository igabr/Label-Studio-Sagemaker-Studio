# Label Studio on SageMaker Studio

Run Label Studio inside SageMaker Studio with a persistent conda env and the Studio proxy.

This repo is meant to get you started with Label Studio for quick experimentation in Sagemaker Studio notebooks.

**Note:** Sagemaker Studio, by default, does not allow docker access without some prior configuration during domain creation and then subsequent docker installation on the instance (see docs [here](https://docs.aws.amazon.com/sagemaker/latest/dg/studio-updated-local-get-started.html)).

As such, the following approach bypasses the need for all of that, by simply following a pip installation route, within a conda environment, and correctly configuring sagemaker studio's JupyterLab proxy to allow access to Label Studio.

## What you’ll upload to your Studio Notebook.
- `bootstrap_labelstudio.sh`

Be sure to save it with **LF line endings** if downloading locally and viewing it in a code editor. In VS Code on Windows: bottom right -> click `CRLF` -> choose `LF` -> save.

This guide assumes you have already set up your studio domain as well as the quick start instance.

---

## 1) Fix the SageMaker Studio IAM policy (one-time)

### Why this matters
Recent changes to `AmazonSageMakerFullAccess` exclude `app/*` using `NotResource`. That blocks `sagemaker:CreateApp` for your user profile. Add a small customer policy to your Studio **Execution Role**.

### Gather these from the AWS Console
- **Domain ID**: SageMaker -> Admin configurations -> Domains -> your domain.
- **User profile name**: same page -> User profiles tab.
- **Execution role**: IAM role shown on the user profile.

### Add a customer-managed policy to the Execution Role
Create a new policy with your values for `<REGION>`, `<ACCOUNT_ID>`, `<DOMAIN_ID>`, `<USER_PROFILE_NAME>` and attach it to the **Execution Role**. Do not edit AWS managed policies.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCreateDeleteAppsForUserProfile",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateApp",
        "sagemaker:DeleteApp",
        "sagemaker:AddTags"
      ],
      "Resource": "arn:aws:sagemaker:<REGION>:<ACCOUNT_ID>:app/<DOMAIN_ID>/user-profile/<USER_PROFILE_NAME>/*/*",
      "Condition": {
        "ArnEquals": {
          "sagemaker:OwnerUserProfileArn": "arn:aws:sagemaker:<REGION>:<ACCOUNT_ID>:user-profile/<DOMAIN_ID>/<USER_PROFILE_NAME>"
        }
      }
    },
    {
      "Sid": "AllowCreateDeleteAppsForPrivateSpaces",
      "Effect": "Allow",
      "Action": [
        "sagemaker:CreateApp",
        "sagemaker:DeleteApp",
        "sagemaker:AddTags"
      ],
      "Resource": "arn:aws:sagemaker:<REGION>:<ACCOUNT_ID>:app/<DOMAIN_ID>/space/*/*/*",
      "Condition": {
        "StringEquals": {
          "sagemaker:SpaceSharingType": "Private"
        }
      }
    }
  ]
}
```

**Trust policy** on the same role should include:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "sagemaker.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
```

If your org uses Service Control Policies or permissions boundaries, check there are no denies on `sagemaker:CreateApp`.

**Apply the change**: stop any running Studio apps, then in the Control Panel click **Launch app -> JupyterLab** to re-assume the role.

---

## 2) First-time setup in Studio

1) **Launch** SageMaker Studio from the console.  
2) In Studio, open a **System terminal**.  
3) **Upload** `bootstrap_labelstudio.sh` to your home directory.  
4) **Make it executable** and **run** it:
```bash
chmod +x bootstrap_labelstudio.sh
./bootstrap_labelstudio.sh
```
5) Answer the prompts:
- **AWS region**. Example: `eu-west-2`
- **Studio base token or full URL**  
  - Token is the part before `.studio` in your Studio URL. Example: `abcd1234` in `https://abcd1234.studio.eu-west-2.sagemaker.aws`
  - You can paste the full URL instead. The script extracts the token.
- **Label Studio username** (email) - this is the desired email address you want to use to login to Label Studio - this does not need to be set up before hand as everything is happening locally on the instance backed by a sqlite database
- **Label Studio password** - desired password (this will be hidden as you type it out)

The script will:
- Create a conda env at `~/conda-envs/labelstudio` if missing.
- Install or upgrade `label-studio` and `label-studio-sdk`.
- Write env files to `~/.labelstudio/`:
  - `static.env` with your username and password
  - `session.env` with your Studio base and proxy host
- Create a launcher at `~/start_labelstudio.sh`.

Now run:
`~/start_labelstudio.sh` in your terminal and this will:

- Start Label Studio on **port 8080** and print a **banner** with the proxy URL:
```
https://<token>.studio.<region>.sagemaker.aws/jupyterlab/default/proxy/8080/
```

Open that URL in your browser to log in. You can now start experimenting with Label Studio via the UI.

---

## 3) Daily use

Start Label Studio any time:
```bash
~/start_labelstudio.sh
```

The launcher:
- Activates the conda env.
- Loads your saved env files.
- Prints the proxy URL in a banner.
- Starts Label Studio.

Projects and data live in `~/labelstudio-data`.

---

## 4) Presigned URLs and logging in

Studio uses short-lived presigned URLs for login.

- If you **keep the Studio tab open** and do not log out of Label Studio, you usually stay signed in.
- If you **log out of Label Studio** or the Studio session expires, open a **fresh Studio URL** from the console, then open the proxy URL again.
- You can also mint a presigned login URL with the CLI and open it immediately:
```bash
aws --region <REGION> sagemaker create-presigned-domain-url \
  --domain-id <DOMAIN_ID> \
  --user-profile-name <USER_PROFILE_NAME> \
  --query AuthorizedUrl --output text
```

The proxy base host (the token before `.studio`) often stays the same across day-to-day restarts. If AWS assigns a new token, re-run `~/start_labelstudio.sh` and paste the new token when prompted, or update `~/.labelstudio/session.env`.

---

## 5) Troubleshooting

**Proxy shows “Unsupported URL path”**  
- Open the **base Studio URL** first to start a fresh session. Then open the proxy URL.

**Bootstrap script won’t run, shows `bash\r`**  
- The file has Windows line endings. Convert to LF in VS Code or run:
```bash
sed -i 's/\r$//' bootstrap_labelstudio.sh
chmod +x bootstrap_labelstudio.sh
./bootstrap_labelstudio.sh
```

**Cannot create apps even after policy change**  
- Check org-level SCPs and any permissions boundaries for denies on `sagemaker:CreateApp`.

**502 or 404 on the proxy**  
- Make sure Label Studio is running in the terminal.  
- Use the printed `/jupyterlab/default/proxy/8080/` path.
---

That’s it. Upload the script, run it once, then use `~/start_labelstudio.sh` for day-to-day experimentation.
