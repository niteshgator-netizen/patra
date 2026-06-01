# PATRA — BUGS OPEN LEDGER

**FILTER APPLIED:** TODO/FIXME scan limited to files touched since 2026-05-01 (Patra-touched files only)
**Author breakdown:** n/a (open markers are file comments, not commits)

Source: codebase scan (TODO/FIXME/HACK/XXX/@deprecated/@broken markers).
Auto-generated 2026-05-31. Total markers found: 63

## CONVENTIONS
- O-XXX = sequential ID
- Each entry shows file:line and the exact comment text

---

## ACTIVE TODO / FIXME / HACK MARKERS

### O-001 | app/controllers/api/v1/accounts/contacts_controller.rb:81
**Type:** TODO
**Comment:** # TODO : refactor this method into dedicated contacts/custom_attributes controller class and routes
**Hot file:** NO

### O-002 | app/controllers/api/v1/accounts/contacts_controller.rb:135
**Type:** TODO
**Comment:** # TODO: Move this to a finder class
**Hot file:** NO

### O-003 | app/helpers/super_admin/features.yml:1
**Type:** TODO
**Comment:** # TODO: Move this values to features.yml itself
**Hot file:** NO

### O-004 | app/javascript/dashboard/components-next/captain/pageComponents/emptyStates/captainEmptyStateContent.js:257
**Type:** XXX
**Comment:** messaging_service_sid: 'MGxxxxxx',
**Hot file:** NO

### O-005 | app/javascript/dashboard/components-next/dropdown-menu/base/DropdownBody.vue:20
**Type:** HACK
**Comment:** // Add extra blur layer only when strong prop is true, as a hack for Chrome's stacked backdrop-blur limitation
**Hot file:** NO

### O-006 | app/javascript/dashboard/components-next/sidebar/SidebarGroup.vue:129
**Type:** TODO
**Comment:** // TODO: Audit the routes and fix the nesting and remove this
**Hot file:** NO

### O-007 | app/javascript/dashboard/components/ChatList.vue:497
**Type:** TODO
**Comment:** // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
**Hot file:** NO

### O-008 | app/javascript/dashboard/components/ChatList.vue:502
**Type:** TODO
**Comment:** // TODO: Remove the usage of useCamelCase after migrating useFilter to camelcase
**Hot file:** NO

### O-009 | app/javascript/dashboard/components/Modal.vue:2
**Type:** TODO
**Comment:** // [TODO] Use Teleport to move the modal to the end of the body
**Hot file:** NO

### O-010 | app/javascript/dashboard/components/Modal.vue:28
**Type:** TODO
**Comment:** // [TODO] Revisit this logic to use outside click directive
**Hot file:** NO

### O-011 | app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:536
**Type:** HACK
**Comment:** // A hacky fix to solve the drag and drop
**Hot file:** NO

### O-012 | app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue:538
**Type:** TODO
**Comment:** // TODO need to find a better solution
**Hot file:** NO

### O-013 | app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue:156
**Type:** HACK
**Comment:** // TODO: This is really hacky, we need to replace the file picker component with
**Hot file:** NO

### O-014 | app/javascript/dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue:158
**Type:** HACK
**Comment:** // Once we have the custom component, we can remove the hacky logic below.
**Hot file:** NO

### O-015 | app/javascript/dashboard/helper/editorHelper.js:567
**Type:** TODO
**Comment:** * TODO: We're hiding captain, enable it back when we add selection improvements
**Hot file:** NO

### O-016 | app/javascript/dashboard/helper/specs/editorHelper.spec.js:33
**Type:** TODO
**Comment:** toDOM: () => ['p', 0], // Represents a paragraph as a <p> tag in the DOM.
**Hot file:** NO

### O-017 | app/javascript/dashboard/helper/specs/editorHelper.spec.js:37
**Type:** TODO
**Comment:** toDOM: node => node.text, // Represents text as its actual string value.
**Hot file:** NO

### O-018 | app/javascript/dashboard/helper/specs/editorHelper.spec.js:47
**Type:** TODO
**Comment:** toDOM: node => [
**Hot file:** NO

### O-019 | app/javascript/dashboard/routes/dashboard/captain/assistants/scenarios/Index.vue:136
**Type:** TODO
**Comment:** // TODO: Add bulk delete endpoint
**Hot file:** NO

### O-020 | app/javascript/dashboard/routes/dashboard/patra/PatraAiTraining.vue:396
**Type:** TODO
**Comment:** <!-- TODO: wire backend — full knowledge-base pair count -->
**Hot file:** NO

### O-021 | app/javascript/dashboard/routes/dashboard/patra/PatraAiTraining.vue:406
**Type:** TODO
**Comment:** <!-- TODO: wire backend — live embedding stats -->
**Hot file:** NO

### O-022 | app/javascript/dashboard/routes/dashboard/patra/PatraAiTraining.vue:411
**Type:** TODO
**Comment:** <!-- TODO: wire backend — AI handle rate -->
**Hot file:** NO

### O-023 | app/javascript/dashboard/routes/dashboard/patra/PatraAiTraining.vue:621
**Type:** TODO
**Comment:** <!-- TODO: wire backend — game / player / agent metadata -->
**Hot file:** NO

### O-024 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:184
**Type:** TODO
**Comment:** <!-- TODO: wire backend -->
**Hot file:** NO

### O-025 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:192
**Type:** TODO
**Comment:** <!-- TODO: wire backend -->
**Hot file:** NO

### O-026 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:233
**Type:** TODO
**Comment:** <!-- TODO: wire backend — KPI drill-down -->
**Hot file:** NO

### O-027 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:481
**Type:** TODO
**Comment:** <!-- TODO: wire backend -->
**Hot file:** NO

### O-028 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:541
**Type:** TODO
**Comment:** <!-- TODO: wire backend -->
**Hot file:** NO

### O-029 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:547
**Type:** TODO
**Comment:** <!-- TODO: wire backend -->
**Hot file:** NO

### O-030 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:565
**Type:** TODO
**Comment:** <!-- TODO: wire backend -->
**Hot file:** NO

### O-031 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:622
**Type:** TODO
**Comment:** <!-- TODO: wire backend -->
**Hot file:** NO

### O-032 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:692
**Type:** TODO
**Comment:** <!-- TODO: wire backend -->
**Hot file:** NO

### O-033 | app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue:728
**Type:** TODO
**Comment:** <!-- TODO: wire backend — agent drill-down -->
**Hot file:** NO

### O-034 | app/javascript/dashboard/routes/dashboard/settings/attributes/AddAttribute.vue:24
**Type:** TODO
**Comment:** // Needs a better data type, todo: refactor this component later
**Hot file:** NO

### O-035 | app/javascript/dashboard/routes/dashboard/settings/billing/Index.vue:53
**Type:** HACK
**Comment:** return plan && plan !== 'hacker';
**Hot file:** NO

### O-036 | app/javascript/dashboard/store/modules/conversations/getters.js:98
**Type:** TODO
**Comment:** // TODO: Replace existing one with V2 after migrating the filters to use camelcase
**Hot file:** NO

### O-037 | app/javascript/dashboard/store/modules/inboxes.js:300
**Type:** TODO
**Comment:** // TODO: Extract other create channel methods to separate files to reduce file size
**Hot file:** NO

### O-038 | app/javascript/v3/views/login/Index.vue:134
**Type:** TODO
**Comment:** // TODO: Remove this when Safari gets wider support
**Hot file:** NO

### O-039 | app/jobs/data_import_job.rb:1
**Type:** TODO
**Comment:** # TODO: logic is written tailored to contact import since its the only import available
**Hot file:** NO

### O-040 | app/models/channel/email.rb:44
**Type:** TODO
**Comment:** # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
**Hot file:** NO

### O-041 | app/models/message.rb:123
**Type:** TODO
**Comment:** # TODO: Get rid of default scope
**Hot file:** NO

### O-042 | app/models/message.rb:401
**Type:** FIXME
**Comment:** # FIXME: Giving it few seconds for the attachment to be uploaded to the service
**Hot file:** NO

### O-043 | app/models/notification.rb:218
**Type:** TODO
**Comment:** # TODO: Rename push_message_title to push_message_body
**Hot file:** NO

### O-044 | app/services/facebook/graph_profile_service.rb:7
**Type:** XXX
**Comment:** # "Player XXXX" display name derived from the PSID's last 4 digits.
**Hot file:** NO

### O-045 | app/services/notification/email_notification_service.rb:19
**Type:** TODO
**Comment:** # TODO : Clean up whatever happening over here
**Hot file:** NO

### O-046 | app/services/payments/escalation_notifier.rb:13
**Type:** TODO
**Comment:** # TODO: Create Chatwoot Notification or send email when notification pattern is confirmed
**Hot file:** NO

### O-047 | app/services/tiktok/messaging_helpers.rb:21
**Type:** TODO
**Comment:** # TODO: Remove this once we show the social_tiktok_user_name in the UI instead of the username
**Hot file:** NO

### O-048 | app/services/whatsapp/providers/whatsapp_cloud_service.rb:92
**Type:** TODO
**Comment:** # TODO: See if we can unify the API versions and for both paths and make it consistent with out facebook app API versions
**Hot file:** NO

### O-049 | config/locales/es.yml:399
**Type:** TODO
**Comment:** view_all_articles: Ver todo
**Hot file:** NO

### O-050 | config/locales/it.yml:140
**Type:** TODO
**Comment:** no_payment_method: Nessun metodo di pagamento trovato. Aggiungi un metodo di pagamento prima di effettuare un acquisto.
**Hot file:** NO

### O-051 | config/locales/pt.yml:399
**Type:** TODO
**Comment:** view_all_articles: Visualizar todos
**Hot file:** NO

### O-052 | config/locales/pt_BR.yml:140
**Type:** TODO
**Comment:** no_payment_method: Nenhum método de pagamento encontrado. Por favor, adicione um método de pagamento antes de realizar uma compra.
**Hot file:** NO

### O-053 | enterprise/app/models/enterprise/account.rb:21
**Type:** TODO
**Comment:** # TODO: Remove this when we upgrade administrate gem to the latest version
**Hot file:** NO

### O-054 | spec/enterprise/jobs/captain/documents/schedule_syncs_job_spec.rb:8
**Type:** HACK
**Comment:** create(:installation_config, name: 'CAPTAIN_DOCUMENT_AUTO_SYNC_INTERVALS', value: { business: 24, hacker: nil }.to_json)
**Hot file:** NO

### O-055 | spec/enterprise/jobs/captain/documents/schedule_syncs_job_spec.rb:25
**Type:** HACK
**Comment:** let(:account) { create(:account, custom_attributes: { plan_name: 'hacker' }) }
**Hot file:** NO

### O-056 | spec/enterprise/models/account_spec.rb:188
**Type:** HACK
**Comment:** 'hacker' => %w[feature1 feature2],
**Hot file:** NO

### O-057 | spec/enterprise/models/account_spec.rb:197
**Type:** HACK
**Comment:** context 'when plan_name is hacker' do
**Hot file:** NO

### O-058 | spec/enterprise/models/account_spec.rb:198
**Type:** HACK
**Comment:** it 'returns the features for the hacker plan' do
**Hot file:** NO

### O-059 | spec/enterprise/models/account_spec.rb:199
**Type:** HACK
**Comment:** account.custom_attributes = { 'plan_name': 'hacker' }
**Hot file:** NO

### O-060 | spec/enterprise/services/enterprise/billing/create_stripe_customer_service_spec.rb:26
**Type:** HACK
**Comment:** { 'name' => 'A Plan Name', 'product_id' => ['prod_hacker_random'], 'price_ids' => ['price_hacker_random'] }
**Hot file:** NO

### O-061 | spec/enterprise/services/enterprise/billing/create_stripe_customer_service_spec.rb:75
**Type:** HACK
**Comment:** .with({ customer: 'cus_random_number', items: [{ price: 'price_hacker_random', quantity: 2 }] })
**Hot file:** NO

### O-062 | spec/enterprise/services/enterprise/billing/create_stripe_customer_service_spec.rb:101
**Type:** HACK
**Comment:** .with({ customer: customer.id, items: [{ price: 'price_hacker_random', quantity: 2 }] })
**Hot file:** NO

### O-063 | spec/enterprise/services/enterprise/billing/create_stripe_customer_service_spec.rb:122
**Type:** HACK
**Comment:** { 'name' => 'A Plan Name', 'product_id' => ['prod_hacker_random'], 'price_ids' => ['price_hacker_random'] }
**Hot file:** NO

---

## NOTES
This file lists what the CODEBASE itself flags as open. It does NOT include bugs Genius knows about that aren't yet marked in code. Genius adds those manually.
