import credits.leo;

// The 'graph_coloring' program.
program graph_coloring_v1.aleo {
    mapping questions: u32 => Question;
    mapping question_idx: bool => u32;

    struct Question {
        target_height: u32,
        best_answer: u8,
        best_submitter: scalar,
        best_answer_digest: scalar,
        proposer: address,
        reward: u64,
        question: [[bool; 32]; 32],
        is_cancelled: bool,
    }

    record Answer {
        owner: address,
        question_id: u32,
        answer: [u8; 32],
    }

    inline invalid_color () -> u8 {
        return 255u8;
    }

    inline program_address () -> address {
        return aleo1p20x8fmqz06mvj3t7lajxu6kg0vtsan8npqpr5qssy3txcsgxcqsepgy56;
    }

    transition add_question (question: [[bool; 32]; 32], target_height: u32, reward: u64, credit: credits.leo/credits) {
        let q: Question = Question{
            target_height: target_height,
            best_answer: 255u8,
            best_submitter: 0scalar,
            best_answer_digest: 0scalar,
            proposer: self.caller,
            reward: reward,
            question: question,
            is_cancelled: false,
        };

        credits.leo/transfer_private_to_public(credit, program_address(), reward);

        return then finalize (q);
    }

    finalize add_question (q: Question) {
        // check height
        assert(block.height < q.target_height);

        // ^_^ Maybe we need to check graph isomorphic in another contract LOL.
        let idx: u32 = Mapping::get_or_use(question_idx, true, 0u32);

        Mapping::set(questions, idx, q);
        Mapping::set(question_idx, true, idx + 1u32);
    }

    transition cancel_stale_question (question_id: u32, reward: u64) {
        credits.leo/transfer_public(self.caller, reward);
        return then finalize (question_id, self.caller, reward);
    }

    finalize cancel_stale_question (question_id: u32, caller: address, reward: u64) {
        let q: Question = Mapping::get(questions, question_id);

        // check height
        assert(block.height > q.target_height);

        // check proposer
        assert_eq(caller, q.proposer);

        // check reward
        assert_eq(reward, q.reward);

        // check if already answered
        assert_eq(q.best_answer, 255u8);
        assert_eq(q.best_submitter, 0scalar);
        assert_eq(q.best_answer_digest, 0scalar);
    }

    transition verify_answer(question: [[bool; 32]; 32], answer: [u8; 32], idx: u32) {
        // check question
        let count: u8 = verify_and_count(answer, question);
        assert_neq(count, invalid_color());

        // TODO: add salty
        let submitter: scalar = BHP256::hash_to_scalar(self.caller);
        let answer_digest: scalar = BHP256::hash_to_scalar(answer);
        let question_digest: scalar = BHP256::hash_to_scalar(question);

        return then finalize (count, idx, submitter, answer_digest, question_digest);
    }

    finalize verify_answer(count: u8, idx: u32, submitter: scalar, answer_digest: scalar, question_digest: scalar) {
        let q: Question = Mapping::get(questions, idx);

        // check height
        assert(block.height < q.target_height);

        // check best answer
        assert(count < q.best_answer);

        // check question digest
        assert_eq(question_digest, BHP256::hash_to_scalar(q.question));

        let new_q: Question = Question {
            target_height: q.target_height,
            best_answer: count,
            best_submitter: submitter,
            best_answer_digest: answer_digest,
            proposer: q.proposer,
            reward: q.reward,
            question: q.question,
            is_cancelled: q.is_cancelled,
        };

        Mapping::set(questions, idx, new_q);
    }

    transition submit_answer(answer: [u8; 32], idx: u32, proposer: address, reward: u64) -> Answer {
        let answer_digest: scalar = BHP256::hash_to_scalar(answer);
        let submitter: scalar = BHP256::hash_to_scalar(self.caller);
        let a: Answer = Answer {
            question_id: idx,
            owner: proposer,
            answer: answer,
        };

        credits.leo/transfer_public_to_private(self.caller, reward);

        return a then finalize (proposer, answer_digest, submitter, idx, reward);
    }

    finalize submit_answer (proposer: address, answer_digest: scalar, submitter: scalar, idx: u32, reward: u64) {
        let q: Question = Mapping::get(questions, idx);

        // check height
        assert(block.height >= q.target_height);

        // check answer
        assert_eq(answer_digest, q.best_answer_digest);

        // check submitter
        assert_eq(submitter, q.best_submitter);

        // check proposer
        assert_eq(proposer, q.proposer);

        // check reward
        assert_eq(reward, q.reward);
    }

    inline verify_and_count (answer: [u8; 32], question: [[bool; 32]; 32]) -> u8 {
        let count: u8 = 0u8;

        for i: u8 in 0u8..32u8 {
            for j: u8 in 0u8..32u8 {
                if i != j {
                    if question[i][j] {
                        if answer[i] == answer[j] {
                            count = invalid_color();
                        }
                    }
                }
            }
            if answer[i] > count {
                count = answer[i];
            }
        }

        return count;
    }
}
