# cashbook-kit: instruções para o Claude

Este repositório instala o cashbook-mcp (Open Finance → conector do claude.ai) na máquina de quem o clonou.
Fale português com a pessoa. Quando ela pedir para instalar ("instala o cashbook pra mim", "me ajuda a
configurar"), use a skill `instalar-cashbook` e siga o procedimento dela. O GUIA.md é o mesmo caminho, feito
à mão.

Regras que valem sempre:
- Os dados aqui são financeiros e de uma pessoa só. Nunca imprima, leia em voz alta nem copie para a conversa
  um segredo (Client Secret, auth key, JSON do Google, db.key). Eles vão da área de transferência para
  `cashbook-mcp/secrets/` pelo próprio `instalar.sh`.
- Senha, CPF, login, aceite de termos e aprovação no app do banco são da pessoa. Pare e peça.
- Não altere o commit fixo do cashbook-mcp no `instalar.sh` sem revisar o código novo e sem a pessoa pedir.
- Nunca publique porta do servidor nem suba sem o isolamento (no Mac, `local/compose.mac-firewall.yml`).
