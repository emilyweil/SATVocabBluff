-- ===========================================
-- VOCAB BLUFF - Supabase Database Schema
-- ===========================================
-- Run this in your Supabase SQL Editor (https://supabase.com/dashboard)

-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- ===========================================
-- TABLES
-- ===========================================

-- Profiles (extends Supabase auth.users)
create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  username text unique not null,
  created_at timestamp with time zone default now()
);

-- Groups (friend circles)
create table public.groups (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  invite_code text unique not null default substring(md5(random()::text) from 1 for 6),
  created_by uuid references public.profiles(id),
  created_at timestamp with time zone default now()
);

-- Group members
create table public.group_members (
  id uuid default uuid_generate_v4() primary key,
  group_id uuid references public.groups(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  joined_at timestamp with time zone default now(),
  unique(group_id, user_id)
);

-- Words (SAT vocabulary)
create table public.words (
  id uuid default uuid_generate_v4() primary key,
  word text unique not null,
  definition text not null,
  example_sentence text
);

-- Rounds (daily game rounds)
create table public.rounds (
  id uuid default uuid_generate_v4() primary key,
  group_id uuid references public.groups(id) on delete cascade,
  word_id uuid references public.words(id),
  truth_holder_id uuid references public.profiles(id),
  phase text default 'submitting' check (phase in ('submitting', 'voting', 'results')),
  created_at timestamp with time zone default now()
);

-- Submissions (definitions - real or fake)
create table public.submissions (
  id uuid default uuid_generate_v4() primary key,
  round_id uuid references public.rounds(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  definition text not null,
  is_truth boolean default false,
  created_at timestamp with time zone default now(),
  unique(round_id, user_id)
);

-- Votes
create table public.votes (
  id uuid default uuid_generate_v4() primary key,
  round_id uuid references public.rounds(id) on delete cascade,
  voter_id uuid references public.profiles(id) on delete cascade,
  submission_id uuid references public.submissions(id) on delete cascade,
  created_at timestamp with time zone default now(),
  unique(round_id, voter_id)
);

-- Scores
create table public.scores (
  id uuid default uuid_generate_v4() primary key,
  group_id uuid references public.groups(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  total_points int default 0,
  fools int default 0,
  correct_guesses int default 0,
  unique(group_id, user_id)
);

-- ===========================================
-- ROW LEVEL SECURITY
-- ===========================================

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.rounds enable row level security;
alter table public.submissions enable row level security;
alter table public.votes enable row level security;
alter table public.scores enable row level security;

create policy "Profiles are viewable by everyone" on public.profiles for select using (true);
create policy "Users can insert own profile" on public.profiles for insert with check (auth.uid() = id);
create policy "Users can update own profile" on public.profiles for update using (auth.uid() = id);

create policy "Members can view their groups" on public.groups for select using (
  exists (select 1 from public.group_members where group_members.group_id = groups.id and group_members.user_id = auth.uid())
  or created_by = auth.uid()
);
create policy "Anyone can view groups by invite code" on public.groups for select using (true);
create policy "Auth users can create groups" on public.groups for insert with check (auth.uid() = created_by);

create policy "Members can view group members" on public.group_members for select using (
  exists (select 1 from public.group_members gm where gm.group_id = group_members.group_id and gm.user_id = auth.uid())
);
create policy "Users can join groups" on public.group_members for insert with check (auth.uid() = user_id);
create policy "Users can leave groups" on public.group_members for delete using (auth.uid() = user_id);

create policy "Members can view rounds" on public.rounds for select using (
  exists (select 1 from public.group_members where group_members.group_id = rounds.group_id and group_members.user_id = auth.uid())
);
create policy "Members can create rounds" on public.rounds for insert with check (
  exists (select 1 from public.group_members where group_members.group_id = group_id and group_members.user_id = auth.uid())
);
create policy "Members can update rounds" on public.rounds for update using (
  exists (select 1 from public.group_members where group_members.group_id = rounds.group_id and group_members.user_id = auth.uid())
);

create policy "Members can view submissions" on public.submissions for select using (
  exists (
    select 1 from public.rounds r
    join public.group_members gm on gm.group_id = r.group_id
    where r.id = submissions.round_id and gm.user_id = auth.uid()
  )
);
create policy "Users can submit" on public.submissions for insert with check (auth.uid() = user_id);

create policy "Members can view votes" on public.votes for select using (
  exists (
    select 1 from public.rounds r
    join public.group_members gm on gm.group_id = r.group_id
    where r.id = votes.round_id and gm.user_id = auth.uid()
  )
);
create policy "Users can vote" on public.votes for insert with check (auth.uid() = voter_id);

create policy "Members can view scores" on public.scores for select using (
  exists (select 1 from public.group_members where group_members.group_id = scores.group_id and group_members.user_id = auth.uid())
);
create policy "Scores can be managed" on public.scores for all using (true);

-- ===========================================
-- AUTO-CREATE PROFILE ON SIGNUP
-- ===========================================

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, username)
  values (new.id, coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)));
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ===========================================
-- 500 CHALLENGING SAT VOCABULARY WORDS
-- From: https://ivymax.com/blog/sat/sat-vocabulary-500-challenging-words/
-- ===========================================

insert into public.words (word, definition, example_sentence) values
('abate', 'to become less intense or widespread', 'The storm began to abate after midnight.'),
('abdicate', 'to renounce one''s throne or power', 'The king chose to abdicate rather than face the revolution.'),
('aberrant', 'departing from an accepted standard', 'His aberrant behavior concerned his teachers.'),
('abhor', 'to regard with disgust and hatred', 'She abhors cruelty of any kind.'),
('abjure', 'to renounce formally a belief or claim', 'He abjured his former political views.'),
('abnegate', 'to renounce or give up something valued', 'She abnegated her claim to the inheritance.'),
('abrogate', 'to repeal or do away with formally', 'The new government abrogated the unfair treaty.'),
('abscond', 'to leave hurriedly and secretly', 'The treasurer absconded with the company funds.'),
('abstruse', 'difficult to understand; obscure', 'The professor''s abstruse lecture confused the students.'),
('accost', 'to approach and speak to someone boldly', 'A stranger accosted me on the street.'),
('acerbic', 'sharp and forthright in speech', 'Her acerbic wit made her a formidable opponent.'),
('acrimonious', 'angry and bitter in speech or tone', 'The divorce became increasingly acrimonious.'),
('adulation', 'excessive praise or admiration', 'The celebrity grew tired of constant adulation.'),
('affable', 'friendly and easy to talk to', 'The affable host made everyone feel welcome.'),
('alacrity', 'cheerful readiness or eagerness', 'She accepted the invitation with alacrity.'),
('altruistic', 'showing selfless concern for others', 'His altruistic nature led him to volunteer regularly.'),
('ameliorate', 'to make something better or improve', 'The new policies helped ameliorate working conditions.'),
('amenable', 'open and responsive to suggestion', 'She was amenable to changing the meeting time.'),
('amorphous', 'lacking a clear structure or form', 'His amorphous ideas needed more development.'),
('anathema', 'something or someone greatly disliked', 'Dishonesty is anathema to her.'),
('anomaly', 'something that deviates from normal', 'The warm December day was an anomaly.'),
('antipathy', 'a deep-seated feeling of dislike', 'There was mutual antipathy between the rivals.'),
('apathy', 'lack of interest or concern', 'Voter apathy led to low turnout.'),
('appease', 'to calm or satisfy someone', 'She tried to appease his anger with an apology.'),
('arcane', 'understood by few; mysterious', 'The arcane rituals fascinated the anthropologist.'),
('ardent', 'enthusiastic or passionate', 'He was an ardent supporter of the cause.'),
('articulate', 'able to express ideas clearly', 'The articulate speaker captivated the audience.'),
('ascetic', 'practicing severe self-discipline', 'The monk lived an ascetic lifestyle.'),
('asperity', 'harshness of tone or manner', 'She spoke with unexpected asperity.'),
('assiduous', 'showing great care and perseverance', 'Her assiduous efforts paid off.'),
('astute', 'having ability to accurately assess situations', 'The astute investor predicted the market shift.'),
('audacious', 'showing willingness to take bold risks', 'His audacious plan surprised everyone.'),
('augment', 'to add to or increase something', 'She augmented her income with freelance work.'),
('auspicious', 'conducive to success; favorable', 'The sunny weather seemed auspicious for the wedding.'),
('austere', 'severe or strict in manner or appearance', 'The austere room had only a bed and desk.'),
('avaricious', 'having extreme greed for wealth', 'The avaricious landlord raised rents constantly.'),
('banal', 'lacking originality or freshness', 'The movie''s banal dialogue disappointed critics.'),
('beguile', 'to charm or enchant deceptively', 'She beguiled him with her stories.'),
('bellicose', 'demonstrating aggression', 'The bellicose nation threatened its neighbors.'),
('benevolent', 'well meaning and kindly', 'The benevolent donor funded the new library.'),
('benign', 'gentle and kind', 'Her benign smile put patients at ease.'),
('blithe', 'showing casual and cheerful indifference', 'He showed blithe disregard for the rules.'),
('boisterous', 'noisy, energetic, and cheerful', 'The boisterous crowd cheered loudly.'),
('bombastic', 'high-sounding but with little meaning', 'His bombastic speech impressed no one.'),
('brazen', 'bold and without shame', 'Her brazen lie shocked everyone.'),
('brevity', 'concise and exact use of words', 'The brevity of his speech was refreshing.'),
('brusque', 'abrupt or blunt in manner', 'His brusque response hurt her feelings.'),
('bucolic', 'relating to pleasant countryside', 'They enjoyed the bucolic scenery of Vermont.'),
('cajole', 'to persuade with flattery', 'She cajoled him into helping her move.'),
('callous', 'showing insensitive disregard for others', 'His callous remarks angered everyone.'),
('candor', 'the quality of being open and honest', 'I appreciate your candor about the situation.'),
('capitulate', 'to surrender or give up resistance', 'The army was forced to capitulate.'),
('capricious', 'given to sudden changes of mood', 'Her capricious nature made her unpredictable.'),
('caustic', 'sarcastic and bitter', 'His caustic humor offended some people.'),
('charlatan', 'a fraud claiming expertise', 'The charlatan sold fake medicine.'),
('chicanery', 'the use of trickery', 'Political chicanery undermined public trust.'),
('clandestine', 'kept secret for illicit purposes', 'They held clandestine meetings at night.'),
('clemency', 'mercy or leniency', 'The prisoner begged for clemency.'),
('coalesce', 'to come together and unite', 'Various groups coalesced to form one movement.'),
('cogent', 'clear, logical, and convincing', 'She made a cogent argument for change.'),
('commensurate', 'corresponding in size or degree', 'Her salary was commensurate with her experience.'),
('complacent', 'showing smug satisfaction with oneself', 'Success made him complacent.'),
('conciliatory', 'intended to make peace', 'His conciliatory tone helped end the argument.'),
('condescend', 'to show feelings of superiority', 'She condescended to speak with the interns.'),
('confluence', 'the junction of two things; merging', 'The confluence of ideas sparked innovation.'),
('conjecture', 'an opinion based on incomplete information', 'His theory was mere conjecture.'),
('consensus', 'general agreement', 'The committee reached a consensus.'),
('contrite', 'feeling remorse or guilt', 'He seemed genuinely contrite about his mistake.'),
('conundrum', 'a confusing problem or question', 'The budget presented a conundrum.'),
('convoluted', 'extremely complex and difficult to follow', 'The convoluted plot confused viewers.'),
('copious', 'abundant in supply or quantity', 'She took copious notes during the lecture.'),
('credulous', 'too ready to believe things', 'The credulous tourist fell for the scam.'),
('cryptic', 'having mysterious or obscure meaning', 'He left a cryptic message.'),
('cursory', 'hasty and not thorough', 'A cursory glance revealed the error.'),
('dearth', 'a scarcity or lack of something', 'There was a dearth of qualified candidates.'),
('debacle', 'a sudden and humiliating failure', 'The product launch was a complete debacle.'),
('decorous', 'keeping with good taste and propriety', 'Her decorous behavior impressed the hosts.'),
('decorum', 'behavior in keeping with good taste', 'Please maintain decorum during the ceremony.'),
('deference', 'humble submission and respect', 'He showed deference to his elders.'),
('deleterious', 'causing harm or damage', 'Smoking has deleterious effects on health.'),
('delineate', 'to describe precisely', 'The report delineated the key issues.'),
('demure', 'reserved, modest, and shy', 'She gave a demure smile.'),
('deride', 'to mock or ridicule', 'Critics derided the new policy.'),
('despot', 'a ruler with absolute power', 'The despot crushed all opposition.'),
('didactic', 'intended to teach with moral instruction', 'The didactic novel bored young readers.'),
('diffident', 'modest or shy from lack of self-confidence', 'The diffident student rarely spoke up.'),
('dilatory', 'slow to act; causing delay', 'His dilatory tactics frustrated everyone.'),
('disingenuous', 'not candid or sincere', 'Her apology seemed disingenuous.'),
('disparage', 'to belittle or speak poorly of', 'He disparaged her achievements.'),
('disperse', 'to spread out or scatter', 'The crowd dispersed after the concert.'),
('disseminate', 'to spread widely', 'They disseminated information through social media.'),
('dogmatic', 'stubbornly asserting opinions as fact', 'His dogmatic views prevented compromise.'),
('dubious', 'doubtful or uncertain', 'I was dubious about his claims.'),
('ebullient', 'cheerful and full of energy', 'Her ebullient personality lit up the room.'),
('eclectic', 'drawing from a wide range of sources', 'She had eclectic taste in music.'),
('egregious', 'outstandingly bad', 'The egregious error cost the company millions.'),
('elucidate', 'to make something clear; explain', 'Could you elucidate your point?'),
('emaciated', 'abnormally thin or weak', 'The emaciated stray dog needed care.'),
('embellish', 'to make more attractive by adding details', 'He embellished the story for effect.'),
('empirical', 'based on observation or experience', 'The theory lacked empirical support.'),
('enervate', 'to weaken or drain energy', 'The heat enervated the hikers.'),
('engender', 'to create or produce a feeling', 'His speech engendered hope.'),
('enigma', 'a person or thing that is mysterious', 'She remained an enigma to her colleagues.'),
('enigmatic', 'difficult to interpret; mysterious', 'The enigmatic smile intrigued everyone.'),
('ennui', 'a feeling of listlessness from lack of excitement', 'Summer ennui set in after a few weeks.'),
('ephemeral', 'lasting for a very short time', 'Fame can be ephemeral.'),
('equitable', 'fair and just', 'They sought an equitable solution.'),
('equivocal', 'unclear or vague', 'His equivocal answer satisfied no one.'),
('equivocate', 'to use ambiguous language to conceal truth', 'The politician equivocated on the issue.'),
('erudite', 'having or showing great knowledge', 'The erudite professor authored many books.'),
('esoteric', 'intended for a small number of people', 'The esoteric subject appealed to specialists.'),
('euphemism', 'a mild word substituted for a harsh one', 'Passed away is a euphemism for died.'),
('exacerbate', 'to make a problem worse', 'His comments exacerbated the conflict.'),
('exculpate', 'to clear from blame or guilt', 'The evidence exculpated the defendant.'),
('exonerate', 'to officially absolve someone of blame', 'DNA evidence exonerated the prisoner.'),
('expeditious', 'done quickly and efficiently', 'We need an expeditious resolution.'),
('expiate', 'to atone for guilt or sin', 'He sought to expiate his crimes.'),
('expunge', 'to get rid of completely', 'She wanted to expunge the record.'),
('extol', 'to praise highly', 'Critics extolled the performance.'),
('extraneous', 'irrelevant', 'Remove extraneous details from your essay.'),
('facilitate', 'to make easier', 'Technology facilitates communication.'),
('fallacious', 'based on a mistaken belief', 'The fallacious argument was easily refuted.'),
('fastidious', 'very attentive to detail', 'She was fastidious about cleanliness.'),
('fatuous', 'silly and pointless', 'His fatuous comments annoyed everyone.'),
('feckless', 'lacking initiative or responsibility', 'The feckless employee was soon fired.'),
('fervent', 'having passionate intensity', 'She made a fervent plea for help.'),
('fervid', 'intensely enthusiastic or passionate', 'His fervid support never wavered.'),
('flagrant', 'obviously offensive', 'It was a flagrant violation of the rules.'),
('flippant', 'not showing a serious attitude', 'Her flippant response upset the teacher.'),
('forbearance', 'restraint and self-control', 'She showed remarkable forbearance.'),
('fortuitous', 'happening by chance, often fortunately', 'Their fortuitous meeting changed everything.'),
('fractious', 'irritable and quarrelsome', 'The fractious committee couldn''t agree.'),
('garrulous', 'excessively talkative', 'The garrulous neighbor talked for hours.'),
('grandiloquent', 'pompous or extravagant in language', 'His grandiloquent speeches bored the audience.'),
('grapple', 'to wrestle, physically or mentally', 'She grappled with the difficult decision.'),
('gratuitous', 'uncalled for; unnecessary', 'The gratuitous violence was disturbing.'),
('gregarious', 'sociable and enjoying company', 'His gregarious nature made him popular.'),
('hackneyed', 'overused and unoriginal', 'The hackneyed phrase added nothing new.'),
('hapless', 'unfortunate', 'The hapless tourist lost his wallet.'),
('harangue', 'a lengthy aggressive speech', 'He delivered a harangue about taxes.'),
('haughty', 'arrogantly superior', 'Her haughty manner alienated colleagues.'),
('hedonist', 'a person devoted to pleasure', 'The hedonist lived only for enjoyment.'),
('hegemony', 'leadership or dominance by one group', 'The empire maintained hegemony for centuries.'),
('heresy', 'belief contrary to accepted doctrine', 'His views were considered heresy.'),
('heterogeneous', 'not uniform; varied', 'The heterogeneous group had diverse opinions.'),
('hubris', 'excessive pride or self-confidence', 'His hubris led to his downfall.'),
('iconoclast', 'a person who attacks cherished beliefs', 'The iconoclast challenged traditions.'),
('idiosyncratic', 'peculiar or individual', 'She had idiosyncratic habits.'),
('ignominious', 'deserving public disgrace', 'The ignominious defeat ended his career.'),
('immutable', 'unchanging over time', 'Some principles are immutable.'),
('impassive', 'showing no emotion', 'His impassive face revealed nothing.'),
('impecunious', 'having little or no money', 'The impecunious artist struggled to pay rent.'),
('impede', 'to prevent or hold back', 'Bureaucracy impedes progress.'),
('imperious', 'arrogantly domineering', 'Her imperious manner offended staff.'),
('impetuous', 'acting quickly without thought', 'His impetuous decision caused problems.'),
('impinge', 'to encroach on', 'The noise impinged on their concentration.'),
('implacable', 'unable to be appeased', 'The implacable enemy refused to negotiate.'),
('impugn', 'to challenge the truth of something', 'He impugned her motives.'),
('impute', 'to attribute something to someone', 'They imputed dishonesty to him unfairly.'),
('inane', 'silly or stupid', 'The inane comments wasted time.'),
('incendiary', 'designed to cause fires or conflict', 'His incendiary remarks sparked outrage.'),
('inchoate', 'just beginning; not fully formed', 'Her inchoate ideas needed development.'),
('incisive', 'intelligently analytical', 'Her incisive analysis impressed everyone.'),
('inconsequential', 'not important', 'The difference was inconsequential.'),
('incontrovertible', 'unable to be denied', 'The evidence was incontrovertible.'),
('incorrigible', 'not able to be corrected or reformed', 'The incorrigible child misbehaved constantly.'),
('indefatigable', 'persisting tirelessly', 'Her indefatigable efforts paid off.'),
('indefensible', 'not justifiable or excusable', 'His actions were indefensible.'),
('indignant', 'feeling anger at unfair treatment', 'She was indignant at the accusation.'),
('indolent', 'wanting to avoid activity; lazy', 'The indolent student rarely did homework.'),
('indomitable', 'impossible to subdue or defeat', 'Her indomitable spirit inspired others.'),
('induce', 'to bring about or cause', 'The medicine induced drowsiness.'),
('ineffable', 'too great to be expressed in words', 'The view was of ineffable beauty.'),
('ineluctable', 'impossible to avoid', 'Death is an ineluctable fate.'),
('inexorable', 'impossible to stop or prevent', 'The inexorable march of time continues.'),
('infallible', 'incapable of making mistakes', 'No one is infallible.'),
('ingenuous', 'innocent and unsuspecting', 'Her ingenuous trust was endearing.'),
('inimical', 'tending to obstruct or harm', 'The policy was inimical to growth.'),
('innocuous', 'benign, not harmful', 'The innocuous remark offended no one.'),
('insatiable', 'impossible to satisfy', 'His insatiable appetite amazed everyone.'),
('insidious', 'proceeding subtly with harmful effects', 'The disease''s insidious progression worried doctors.'),
('insipid', 'lacking flavor or interest', 'The insipid food disappointed guests.'),
('insolent', 'showing rude lack of respect', 'His insolent reply angered the teacher.'),
('instigate', 'to bring about; incite', 'He instigated the rebellion.'),
('insular', 'ignorant of other cultures', 'Their insular views limited understanding.'),
('intangible', 'unable to be touched; not physical', 'Trust is an intangible asset.'),
('intractable', 'hard to control or deal with', 'The intractable problem persisted.'),
('intransigent', 'unwilling to change views', 'The intransigent negotiator blocked progress.'),
('intrepid', 'fearless and adventurous', 'The intrepid explorer crossed the desert.'),
('inure', 'to accustom to something unpleasant', 'Years of hardship inured her to difficulty.'),
('inveterate', 'having a long-established habit', 'He was an inveterate liar.'),
('irascible', 'easily angered', 'The irascible coach yelled constantly.'),
('itinerant', 'traveling from place to place', 'Itinerant workers followed the harvest.'),
('jettison', 'to throw or discard something unnecessary', 'They jettisoned the failing plan.'),
('jingoistic', 'extremely patriotic, often aggressively', 'His jingoistic rhetoric alarmed allies.'),
('judicious', 'having good judgment', 'She made a judicious decision.'),
('juxtapose', 'to place side by side for comparison', 'The exhibit juxtaposed old and new art.'),
('laconic', 'using very few words', 'His laconic reply was just no.'),
('lament', 'to mourn or express sorrow', 'She lamented the loss of her friend.'),
('languid', 'weak or faint from fatigue', 'The languid summer heat made everyone drowsy.'),
('largesse', 'generosity in bestowing gifts', 'The benefactor''s largesse funded the museum.'),
('latent', 'existing but not yet developed', 'Her latent talent emerged in college.'),
('laudatory', 'expressing praise or admiration', 'The laudatory review boosted sales.'),
('lethargic', 'sluggish and apathetic', 'He felt lethargic after the heavy meal.'),
('licentious', 'unrestrained by law or morality', 'The licentious behavior shocked the community.'),
('lithe', 'flexible, supple, and graceful', 'The lithe dancer moved beautifully.'),
('loquacious', 'tending to talk a great deal', 'The loquacious host dominated conversation.'),
('lucid', 'clear and easily understandable', 'Her lucid explanation helped everyone.'),
('lugubrious', 'looking or sounding sad and dismal', 'The lugubrious music matched the mood.'),
('lurid', 'very vivid in color or shocking', 'The lurid details disturbed readers.'),
('maelstrom', 'a powerful storm; turmoil', 'The scandal created a political maelstrom.'),
('magnanimous', 'generous, especially toward a rival', 'The magnanimous winner congratulated his opponent.'),
('malevolent', 'having or showing a wish to do evil', 'The malevolent villain plotted revenge.'),
('malleable', 'easily influenced or shaped', 'Young minds are malleable.'),
('marred', 'damaged or spoiled in quality', 'The celebration was marred by rain.'),
('maudlin', 'self-pityingly sentimental', 'His maudlin poetry embarrassed readers.'),
('maverick', 'independent-minded person', 'The maverick senator voted against her party.'),
('mendacious', 'not telling the truth; lying', 'His mendacious claims were exposed.'),
('mercurial', 'subject to sudden changes of mood', 'Her mercurial temperament confused colleagues.'),
('meretricious', 'appearing attractive but having little value', 'The meretricious design hid poor quality.'),
('meticulous', 'showing great attention to detail', 'Her meticulous research was thorough.'),
('misanthropic', 'disliking humankind', 'His misanthropic views isolated him.'),
('mitigate', 'to make less severe', 'They tried to mitigate the damage.'),
('modicum', 'a small quantity of something', 'He showed a modicum of respect.'),
('mollify', 'to soothe someone''s anger', 'She tried to mollify the upset customer.'),
('momentous', 'important or significant', 'It was a momentous occasion.'),
('morass', 'a mess; complicated situation', 'The project became a morass of problems.'),
('morose', 'sullen and ill-tempered', 'His morose mood affected everyone.'),
('munificent', 'more generous than necessary', 'The munificent donation surprised everyone.'),
('myriad', 'countless or extremely large in number', 'There were myriad reasons to celebrate.'),
('nadir', 'lowest point', 'His career reached its nadir.'),
('nascent', 'in the process of coming into existence', 'The nascent democracy faced challenges.'),
('nebulous', 'unclear, vague, or ill-defined', 'Her nebulous plans worried investors.'),
('nefarious', 'wicked or criminal', 'The nefarious scheme was uncovered.'),
('negligent', 'failing to do something; neglectful', 'The negligent driver caused the accident.'),
('neophyte', 'a beginner or novice', 'The neophyte made rookie mistakes.'),
('noisome', 'disagreeable; having offensive smell', 'The noisome garbage needed removal.'),
('nonchalant', 'casually calm and relaxed', 'She acted nonchalant despite the pressure.'),
('noxious', 'poisonous; harmful', 'The noxious fumes forced evacuation.'),
('obdurate', 'stubbornly refusing to change', 'The obdurate negotiator wouldn''t compromise.'),
('obfuscate', 'to make obscure or unclear', 'Legal jargon obfuscates the meaning.'),
('oblique', 'not direct or straightforward', 'She made an oblique reference to the scandal.'),
('oblivious', 'lacking awareness of something', 'He was oblivious to the danger.'),
('obscure', 'not well-known; hard to understand', 'The obscure reference confused readers.'),
('obsequious', 'excessively obedient or attentive', 'His obsequious manner annoyed the boss.'),
('obsolete', 'no longer used; out of date', 'The technology became obsolete quickly.'),
('obstinate', 'stubbornly refusing to change', 'The obstinate child refused to cooperate.'),
('obstreperous', 'noisy and difficult to control', 'The obstreperous crowd disrupted the meeting.'),
('obtrusive', 'noticeable in an unwelcome way', 'The obtrusive advertising annoyed viewers.'),
('officious', 'self-assertive, overbearing', 'The officious clerk delayed everyone.'),
('ominous', 'foreboding or foreshadowing evil', 'Dark clouds gathered ominously.'),
('onerous', 'involving great effort or difficulty', 'The onerous task took months.'),
('opulent', 'rich and luxurious', 'The opulent mansion impressed visitors.'),
('ostensible', 'stated or appearing true, but not necessarily', 'The ostensible reason hid her true motive.'),
('ostentatious', 'characterized by pretentious display', 'His ostentatious wealth alienated neighbors.'),
('ostracism', 'exclusion from a group', 'She faced ostracism after the scandal.'),
('palliate', 'to lessen severity without curing', 'Medicine can palliate symptoms.'),
('panacea', 'a solution for all problems', 'There is no panacea for poverty.'),
('paradigm', 'typical example or pattern; a model', 'The company became a paradigm of success.'),
('paragon', 'a perfect example of a quality', 'She was a paragon of virtue.'),
('pariah', 'an outcast or rejected person', 'The whistleblower became a pariah.'),
('parsimonious', 'unwilling to spend money', 'The parsimonious boss refused raises.'),
('partisan', 'strongly supporting a cause or group', 'Partisan politics blocked compromise.'),
('paucity', 'the presence of something in small amount', 'There was a paucity of evidence.'),
('pedantic', 'excessively concerned with minor details', 'His pedantic corrections irritated everyone.'),
('pejorative', 'expressing contempt or disapproval', 'The pejorative term offended many.'),
('pellucid', 'clear and easy to understand', 'Her pellucid prose was a pleasure to read.'),
('penchant', 'habitual liking for something', 'She had a penchant for adventure.'),
('penurious', 'poverty-stricken', 'The penurious family struggled daily.'),
('perfidious', 'deceitful and untrustworthy', 'The perfidious ally betrayed them.'),
('perfunctory', 'carried out with minimum effort', 'He gave a perfunctory nod.'),
('pernicious', 'having harmful effect, especially gradually', 'The pernicious rumor damaged her reputation.'),
('perspicacious', 'having keen insight and understanding', 'The perspicacious detective solved the case.'),
('perspicuous', 'clearly expressed and easy to understand', 'His perspicuous writing helped students learn.'),
('pertinacious', 'holding firmly to a course; determined', 'Her pertinacious efforts finally succeeded.'),
('peruse', 'to read carefully and thoroughly', 'She perused the contract before signing.'),
('petulant', 'childishly sulky or bad-tempered', 'His petulant response revealed immaturity.'),
('philanthropic', 'seeking to promote welfare of others', 'Her philanthropic work helped thousands.'),
('phlegmatic', 'having unemotional and calm disposition', 'His phlegmatic nature kept him composed.'),
('pithy', 'concise and forcefully expressive', 'Her pithy remarks were memorable.'),
('placate', 'to calm or pacify someone', 'She tried to placate the angry customer.'),
('placid', 'not easily upset or excited', 'The placid lake reflected the mountains.'),
('platitude', 'a remark that has been used too often', 'His speech was full of platitudes.'),
('plethora', 'an excessive amount of something', 'There was a plethora of options.'),
('polemic', 'a strong verbal or written attack', 'His polemic against the policy was fierce.'),
('postulate', 'to assume as true', 'Scientists postulated a new theory.'),
('pragmatic', 'dealing with things sensibly and realistically', 'She took a pragmatic approach.'),
('precarious', 'not securely held or stable', 'His position was precarious.'),
('preclude', 'to prevent from taking place', 'Rain precluded outdoor activities.'),
('precocious', 'having developed abilities earlier than usual', 'The precocious child read at age three.'),
('predilection', 'a preference or liking for something', 'She had a predilection for spicy food.'),
('premonition', 'a strong feeling something is about to happen', 'He had a premonition of danger.'),
('prescient', 'having knowledge of events before they happen', 'The prescient warning saved lives.'),
('prevaricate', 'to speak or act in an evasive way', 'He prevaricated when asked directly.'),
('probity', 'the quality of having strong moral principles', 'Her probity was beyond question.'),
('proclivity', 'the tendency toward', 'He had a proclivity for risk-taking.'),
('prodigious', 'remarkably great in extent or degree', 'She had prodigious talent.'),
('profligate', 'recklessly extravagant or wasteful', 'His profligate spending led to bankruptcy.'),
('profound', 'showing deep knowledge or insight', 'The book offered profound insights.'),
('prohibitive', 'too expensive to afford', 'The prohibitive cost deterred buyers.'),
('prolific', 'producing much fruit, offspring, or work', 'The prolific author wrote fifty novels.'),
('promulgate', 'to promote widely', 'They promulgated the new regulations.'),
('prosaic', 'lacking imagination or originality', 'The prosaic report bored everyone.'),
('proscribe', 'to forbid by law', 'The government proscribed the organization.'),
('protean', 'able to change or adapt easily', 'Her protean abilities impressed employers.'),
('prudent', 'acting with care for the future', 'It would be prudent to save money.'),
('puerile', 'childishly silly', 'His puerile jokes annoyed adults.'),
('pugnacious', 'eager or quick to argue or fight', 'The pugnacious player got many penalties.'),
('punctilious', 'paying attention to detail', 'She was punctilious about etiquette.'),
('quagmire', 'a complex or hazardous situation', 'The project became a legal quagmire.'),
('quandary', 'state of perplexity; a dilemma', 'She found herself in a quandary.'),
('querulous', 'complaining in a petulant manner', 'The querulous patient annoyed nurses.'),
('quiescent', 'in a state of inactivity or dormancy', 'The volcano has been quiescent for decades.'),
('quintessential', 'representing the most perfect example', 'It was the quintessential summer day.'),
('quixotic', 'exceedingly idealistic; impractical', 'His quixotic quest for perfection failed.'),
('rancor', 'long-standing bitterness or resentment', 'There was no rancor between the former rivals.'),
('rancorous', 'characterized by bitterness', 'The rancorous debate divided the committee.'),
('rebuke', 'to criticize sharply', 'The teacher rebuked the disruptive student.'),
('recalcitrant', 'having uncooperative attitude toward authority', 'The recalcitrant teenager defied rules.'),
('recluse', 'a person who lives a solitary life', 'The recluse rarely left home.'),
('reclusive', 'avoiding company of other people', 'The reclusive author refused interviews.'),
('rectify', 'to fix or correct', 'We must rectify this mistake immediately.'),
('redolent', 'strongly reminiscent of something', 'The kitchen was redolent of cinnamon.'),
('refute', 'to prove wrong by argument or evidence', 'She refuted his claims with data.'),
('relegate', 'to assign to a lower position', 'He was relegated to a minor role.'),
('remiss', 'lacking care or attention to duty', 'She was remiss in her responsibilities.'),
('reprieve', 'a cancellation of a punishment', 'The governor granted a reprieve.'),
('reproach', 'to express disapproval', 'His behavior was beyond reproach.'),
('reprobate', 'an unprincipled or immoral person', 'The reprobate wasted his inheritance.'),
('repudiate', 'to reject or refuse to accept', 'She repudiated the allegations.'),
('rescind', 'to revoke, cancel, or repeal', 'The company rescinded the policy.'),
('resilient', 'able to recover quickly from difficulties', 'Children are remarkably resilient.'),
('resolute', 'determined and unwavering', 'She remained resolute despite obstacles.'),
('reticent', 'not revealing thoughts or feelings readily', 'He was reticent about his past.'),
('rhetoric', 'persuasive speaking or writing', 'Her rhetoric moved the audience.'),
('ribald', 'improper; lewd', 'His ribald humor offended some guests.'),
('rife', 'filled with; widespread', 'The city was rife with rumors.'),
('sagacious', 'having keen mental discernment', 'The sagacious leader anticipated problems.'),
('salient', 'most noticeable or important', 'The salient points were clear.'),
('sanctimonious', 'making a show of being morally superior', 'His sanctimonious attitude irritated colleagues.'),
('sanguine', 'optimistic, especially in a bad situation', 'She remained sanguine despite setbacks.'),
('sardonic', 'grimly mocking or cynical', 'His sardonic wit could be cutting.'),
('scrupulous', 'diligent and extremely attentive to detail', 'She was scrupulous about accuracy.'),
('scurrilous', 'spreading disparaging claims; slanderous', 'The scurrilous article damaged his reputation.'),
('sedulous', 'showing dedication and diligence', 'Her sedulous work ethic impressed everyone.'),
('serendipity', 'chance or good luck', 'They met by serendipity at the bookstore.'),
('servile', 'showing excessive willingness to serve', 'His servile behavior embarrassed everyone.'),
('solicitous', 'showing interest or concern', 'She was solicitous about his health.'),
('somnolent', 'sleepy or drowsy', 'The somnolent audience struggled to stay awake.'),
('spurious', 'not genuine, false or fake', 'The spurious claims were debunked.'),
('stagnant', 'showing no activity; dull', 'The economy remained stagnant.'),
('staid', 'sedate and respectable', 'The staid banker surprised everyone with his humor.'),
('stipulate', 'to clearly state conditions', 'The contract stipulates payment terms.'),
('stoic', 'enduring pain without showing feelings', 'He remained stoic during the crisis.'),
('stolid', 'calm and dependable', 'The stolid officer remained composed.'),
('stringent', 'strict, precise, and exacting', 'The stringent requirements excluded many.'),
('stymie', 'to prevent or hinder progress', 'Regulations stymied innovation.'),
('subjugate', 'to bring under control or domination', 'The empire sought to subjugate its neighbors.'),
('succinct', 'briefly and clearly expressed', 'Her succinct summary saved time.'),
('supercilious', 'behaving as if one is superior', 'His supercilious manner alienated people.'),
('superfluous', 'unnecessary, being more than enough', 'Remove superfluous words from your essay.'),
('supplant', 'to take over or replace', 'Digital cameras supplanted film.'),
('surfeit', 'excessive amount', 'There was a surfeit of candidates.'),
('surmise', 'to guess without proof', 'I can only surmise her motives.'),
('surreptitious', 'kept secret, especially because not approved', 'He took a surreptitious glance at his phone.'),
('sycophant', 'a person who flatters someone important', 'The sycophant agreed with everything the boss said.'),
('tacit', 'understood without being stated', 'They had a tacit agreement.'),
('taciturn', 'reserved in speech', 'The taciturn man rarely spoke.'),
('tangential', 'only slightly connected or relevant', 'His comment was tangential to the discussion.'),
('temerity', 'excessive confidence or boldness', 'She had the temerity to challenge the CEO.'),
('tenable', 'reasonable, maintainable', 'Her position was no longer tenable.'),
('tenacious', 'persistent', 'His tenacious efforts finally paid off.'),
('terse', 'sparing in use of words; abrupt', 'Her terse reply ended the conversation.'),
('timorous', 'showing nervousness', 'The timorous speaker struggled with stage fright.'),
('torpid', 'mentally or physically inactive', 'The torpid economy needed stimulation.'),
('transient', 'lasting only for a short time', 'Youth is transient.'),
('transitory', 'not permanent; temporary', 'Fame can be transitory.'),
('travesty', 'a false representation of something', 'The trial was a travesty of justice.'),
('trenchant', 'vigorous or incisive in expression', 'Her trenchant criticism was hard to ignore.'),
('truculent', 'eager or quick to argue or fight', 'The truculent child argued about everything.'),
('turpitude', 'depraved or wicked behavior', 'Moral turpitude disqualified him.'),
('ubiquitous', 'present, appearing, or found everywhere', 'Smartphones are now ubiquitous.'),
('umbrage', 'offense or annoyance', 'She took umbrage at his comment.'),
('unconventional', 'acting outside of the norm', 'Her unconventional methods worked.'),
('unctuous', 'excessively flattering or ingratiating', 'His unctuous manner was off-putting.'),
('undulate', 'to move in a wave-like pattern', 'The hills undulated across the landscape.'),
('unequivocal', 'leaving no doubt; unambiguous', 'Her support was unequivocal.'),
('unmitigated', 'not lessened; absolute', 'The project was an unmitigated disaster.'),
('untenable', 'not able to be maintained or defended', 'His position became untenable.'),
('upbraid', 'to scold or find fault with someone', 'She upbraided him for his lateness.'),
('urbane', 'courteous and refined in manner', 'The urbane diplomat charmed everyone.'),
('usury', 'unethical money lending', 'The laws against usury protected borrowers.'),
('vacillate', 'to alternate between opinions', 'He vacillated between options.'),
('vacuous', 'having lack of thought or intelligence', 'Her vacuous remarks impressed no one.'),
('venerate', 'to regard with great respect', 'The community venerated its elders.'),
('veracity', 'conformity to facts; accuracy', 'I questioned the veracity of his claims.'),
('verbose', 'using more words than needed', 'His verbose writing needed editing.'),
('vestige', 'trace or remnant of something gone', 'Only vestiges of the old building remained.'),
('vex', 'to make someone annoyed or worried', 'The problem continued to vex researchers.'),
('vicarious', 'experienced through another person', 'She lived vicariously through her children.'),
('vicissitude', 'a change of circumstances', 'They weathered the vicissitudes of fortune.'),
('vilify', 'to speak about in a disparaging manner', 'The press vilified the politician.'),
('vindicate', 'to clear from blame or suspicion', 'The evidence vindicated her.'),
('virtuoso', 'highly skilled person, especially in arts', 'The virtuoso pianist amazed the audience.'),
('virulent', 'extremely severe or harmful', 'The virulent disease spread rapidly.'),
('viscous', 'having thick, sticky consistency', 'The viscous liquid poured slowly.'),
('vitriolic', 'filled with bitter criticism', 'Her vitriolic attack surprised everyone.'),
('vituperative', 'bitter and abusive in language', 'His vituperative rant offended all.'),
('vociferous', 'loud and forceful in expressing opinions', 'Vociferous protests filled the streets.'),
('volatile', 'likely to change suddenly and unpredictably', 'The volatile market worried investors.'),
('voracious', 'wanting great quantities of something', 'She was a voracious reader.'),
('wane', 'to decrease in size or intensity', 'Interest in the topic began to wane.'),
('wanton', 'deliberate and unprovoked; reckless', 'The wanton destruction shocked everyone.'),
('wistful', 'showing vague or regretful longing', 'She gave a wistful smile.'),
('wry', 'using dry or mocking humor', 'His wry observation made everyone laugh.'),
('zeal', 'great energy or enthusiasm', 'She pursued the project with zeal.'),
('zealous', 'showing great passion or energy', 'The zealous volunteer worked overtime.'),
('zenith', 'the highest point reached by something', 'Her career reached its zenith.');
